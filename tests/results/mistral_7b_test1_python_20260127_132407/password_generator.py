import secrets
def generate_password(length=16):
	return ''.join(secrets.choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$!') for _ in range(length))
if __name__ == '__main__':
	for _ in range(3):
		print(generate_password())
