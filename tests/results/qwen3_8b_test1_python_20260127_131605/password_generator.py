import secrets
import string

def generate_password(length=16):
    """Generate a cryptographically secure password."""
    characters = string.ascii_letters + string.digits + string.punctuation
    return ''.join(secrets.choice(characters) for _ in range(length))

if __name__ == "__main__":
    print("Password 1:", generate_password())
    print("Password 2:", generate_password())
    print("Password 3:", generate_password())
