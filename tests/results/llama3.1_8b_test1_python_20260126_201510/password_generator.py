import secrets

def generate_password(length=16):
    return ''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz') for _ in range(length))

if __name__ == '__main__':
    print(generate_password())
    print(generate_password())
    print(generate_password())
