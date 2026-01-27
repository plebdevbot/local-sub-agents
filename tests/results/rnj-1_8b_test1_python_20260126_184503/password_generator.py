#!/usr/bin/env python3
import secrets

def generate_password(length=16):
    """Generate a secure random password using secrets module.
    Uses hex encoding for better character distribution.
    """
    return secrets.token_hex(length // 2)[:length]

if __name__ == '__main__':
    # Print 3 sample passwords
    for i in range(3):
        print(generate_password())
