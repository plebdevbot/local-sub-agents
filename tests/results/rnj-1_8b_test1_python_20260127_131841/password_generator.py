#!/usr/bin/env python3
import secrets
import string

def generate_password(length=16):
    alphabet = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.SystemRandom().choice(alphabet) for _ in range(length))

if __name__ == "__main__":
    for _ in range(3):
        print(generate_password())
