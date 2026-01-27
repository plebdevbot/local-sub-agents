import secrets

def generate_password(length=16):
    return ''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz0123456789') for _ in range(length))

def main():
    print(generate_password())
    print(generate_password())
    print(generate_password())
if __name__ == '__main__':
    main()

