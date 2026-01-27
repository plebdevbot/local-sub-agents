import secrets
import string

def generate_password(length=16):
    """Generate a random password of given length."""
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

if __name__ == "__main__":
    for _ in range(3):
        print(generate_password())
