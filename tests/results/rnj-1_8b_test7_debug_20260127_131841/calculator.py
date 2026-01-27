def calculate_average(numbers):
    """Calculate the average of a list of numbers."""
    total = sum(numbers)
    # FIX: Use len(numbers) instead of undefined 'count'
    return total / len(numbers)

def main():
    scores = [85, 92, 78, 95, 88]
    avg = calculate_average(scores)
    print(f"Average score: {avg}")

if __name__ == "__main__":
    main()
