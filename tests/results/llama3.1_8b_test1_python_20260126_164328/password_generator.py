import random
import string
import secrets
def generate_password(length=16):
    all_characters = string.ascii_letters + string.digits
    return ''.join(secrets.choice(all_characters) for _ in range(length))
if __name__ == '__main__':
    print(generate_password())
    print(generate_password())
    print(generate_password())
