import secrets
import string

def generate_password(length=16):
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

if __name__ == '__main__':
    print(generate_password())
    print(generate_password())
    print(generate_password())
