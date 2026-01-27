#!/usr/bin/env python3
import secrets

def generate_password(length=16):
    """Generate a secure random password of specified length."""
    return secrets.token_hex(length // 2)

if __name__ == '__main__':
    for _ in range(3):
        print(generate_password())
