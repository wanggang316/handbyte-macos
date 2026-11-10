import CoreGraphics

/// Squarified treemap layout: each value gets a rectangle with an area in
/// proportion to the value, and the rectangles are kept close to squares so
/// that small items stay visible and easy to hit.
public enum Treemap {
    /// Returns one rectangle for each value, in the order of `values`. A
    /// value that is not positive gets `.zero`.
    public static func layout(values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        // Largest first; equal values keep their input order.
        let order = values.indices.filter { values[$0] > 0 }.sorted {
            values[$0] != values[$1] ? values[$0] > values[$1] : $0 < $1
        }
        var free = bounds
        var row: [Int] = []
        var rowArea = 0.0

        func worstRatio(_ area: Double, smallest: Double, largest: Double, side: Double) -> Double {
            let square = side * side
            return max(square * largest / (area * area), area * area / (square * smallest))
        }

        func place() {
            guard !row.isEmpty else { return }
            let alongWidth = free.width < free.height
            let side = Double(alongWidth ? free.width : free.height)
            let thickness = rowArea / side
            var offset = 0.0
            for index in row {
                let length = values[index] * scale / thickness
                result[index] = alongWidth
                    ? CGRect(x: Double(free.minX) + offset, y: Double(free.minY), width: length, height: thickness)
                    : CGRect(x: Double(free.minX), y: Double(free.minY) + offset, width: thickness, height: length)
                offset += length
            }
            if alongWidth {
                free = CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: max(0, free.height - thickness))
            } else {
                free = CGRect(x: free.minX + thickness, y: free.minY, width: max(0, free.width - thickness), height: free.height)
            }
            row.removeAll(keepingCapacity: true)
            rowArea = 0
        }

        for index in order {
            let area = values[index] * scale
            let side = Double(min(free.width, free.height))
            if let first = row.first, let last = row.last {
                // The row is sorted, so its first cell is the largest. A new
                // cell joins the row only when the row does not get worse.
                let largest = values[first] * scale
                let now = worstRatio(rowArea, smallest: values[last] * scale, largest: largest, side: side)
                let then = worstRatio(rowArea + area, smallest: area, largest: largest, side: side)
                if then > now { place() }
            }
            row.append(index)
            rowArea += area
        }
        place()
        return result
    }
}
