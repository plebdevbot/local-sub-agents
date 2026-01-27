def calculate_average(numbers):
    """Calculate the average of a list of numbers."""
    total = sum(numbers)
    # BUG: Using undefined variable 'count' instead of len(numbers)
    return total / count

def main():
    scores = [85, 92, 78, 95, 88]
    avg = calculate_average(scores)
    print(f"Average score: {avg}")

if __name__ == "__main__":
    main()
