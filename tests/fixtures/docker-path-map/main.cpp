#include <cstdint>

int helper(int value) {
    int doubled = value * 2;
    return doubled + 1;
}

int main() {
    return helper(3);
}
