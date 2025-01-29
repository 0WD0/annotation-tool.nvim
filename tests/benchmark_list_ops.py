import time
import sys

def test_extend():
    start = time.time()
    result = []
    for i in range(10000):
        result.extend(range(100))
    end = time.time()
    return end - start, sys.getsizeof(result)

def test_plus():
    start = time.time()
    result = []
    for i in range(10000):
        result = result + list(range(100))
    end = time.time()
    return end - start, sys.getsizeof(result)

extend_time, extend_size = test_extend()
plus_time, plus_size = test_plus()

print(f"extend: {extend_time:.4f}s, {extend_size} bytes")
print(f"+: {plus_time:.4f}s, {plus_size} bytes")
