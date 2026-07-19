public struct LocationConverter {
    private let lineStartOffsets: [Int]

    public init(source: String) {
        var offsets: [Int] = [0]
        for (index, char) in source.utf8.enumerated() {
            if char == UInt8(ascii: "\n") {
                offsets.append(index + 1)
            }
        }
        self.lineStartOffsets = offsets
    }

    public func lineAndColumn(for utf8Offset: Int) -> (line: Int, column: Int) {
        var low = 0
        var high = lineStartOffsets.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= utf8Offset { low = mid + 1 } else { high = mid - 1 }
        }
        let line = low
        let column = utf8Offset - lineStartOffsets[low - 1] + 1
        return (line, column)
    }
}
