import Foundation

struct ArrayHelper {
    // Bug: off-by-one — the last valid index of a non-empty array is count - 1, not count.
    static func lastIndex<T>(of array: [T]) -> Int {
        array.count
    }
}
