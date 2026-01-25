import sys
import os

def remove_comments_swift(source):
    i = 0
    n = len(source)
    output = []
    
    # States
    in_string = False
    in_multiline = False
    in_line_comment = False
    block_comment_depth = 0
    
    while i < n:
        # Check sequences
        
        # 1. Inside String "..."
        if in_string:
            output.append(source[i])
            if source[i] == '\\':
                if i + 1 < n:
                    i += 1
                    output.append(source[i])
            elif source[i] == '"':
                in_string = False
            i += 1
            continue
            
        # 2. Inside Multiline String """..."""
        if in_multiline:
            if source.startswith('"""', i):
                # Check for escaped triple quote \"""
                # We do this by tracking the backslash in the loop below?
                # No, simpler: check if it's NOT escaped.
                # Since we handle backslash inside this block, we should be fine.
                # However, if we hit """ here, we assume it's the end.
                output.append('"""')
                i += 3
                in_multiline = False
            elif source[i] == '\\':
                 output.append(source[i])
                 if i + 1 < n:
                     i += 1
                     output.append(source[i])
                 i += 1
            else:
                output.append(source[i])
                i += 1
            continue
            
        # 3. Inside Line Comment //...
        if in_line_comment:
            if source[i] == '\n':
                in_line_comment = False
                output.append(source[i]) # Keep the newline
            i += 1
            continue
            
        # 4. Inside Block Comment /*...*/
        if block_comment_depth > 0:
            if source.startswith('/*', i):
                block_comment_depth += 1
                i += 2
            elif source.startswith('*/', i):
                block_comment_depth -= 1
                i += 2
                # If we are not completely out, we continue
                # We do NOT append anything while in comment
            else:
                i += 1
            continue
            
        # 5. CODE STATE (Normal)
        
        # Check start of Multiline String
        if source.startswith('"""', i):
            output.append('"""')
            in_multiline = True
            i += 3
            continue
            
        # Check start of String
        if source[i] == '"':
            output.append('"')
            in_string = True
            i += 1
            continue
            
        # Check start of Line Comment
        if source.startswith('//', i):
            in_line_comment = True
            i += 2
            continue
            
        # Check start of Block Comment
        if source.startswith('/*', i):
            block_comment_depth = 1
            i += 2
            continue
            
        # Normal character
        output.append(source[i])
        i += 1
        
    return "".join(output)

def process_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content = remove_comments_swift(content)
    
    if new_content != content:
        print(f"Cleaning {file_path}")
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
    else:
        print(f"No comments found in {file_path}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 clean_comments.py <directory>")
        sys.exit(1)
        
    root_dir = sys.argv[1]
    
    # Supported extensions
    extensions = ['.swift']
    
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            _, ext = os.path.splitext(filename)
            if ext in extensions:
                full_path = os.path.join(dirpath, filename)
                try:
                    process_file(full_path)
                except Exception as e:
                    print(f"Error processing {full_path}: {e}")

if __name__ == "__main__":
    main()
