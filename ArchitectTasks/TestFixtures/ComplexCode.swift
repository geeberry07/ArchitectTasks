import Foundation

// This file has intentional complexity issues

func veryLongFunction(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {
    // Too many parameters (6 > 5)
    let x1 = a + b
    let x2 = c + d
    let x3 = e + f
    let x4 = x1 + x2
    let x5 = x3 + x4
    let x6 = x5 * 2
    let x7 = x6 / 3
    let x8 = x7 + 1
    let x9 = x8 - 1
    let x10 = x9 * x1
    let x11 = x10 + x2
    let x12 = x11 - x3
    let x13 = x12 * x4
    let x14 = x13 + x5
    let x15 = x14 - x6
    let x16 = x15 * x7
    let x17 = x16 + x8
    let x18 = x17 - x9
    let x19 = x18 * x10
    let x20 = x19 + x11
    let x21 = x20 - x12
    let x22 = x21 * x13
    let x23 = x22 + x14
    let x24 = x23 - x15
    let x25 = x24 * x16
    let x26 = x25 + x17
    let x27 = x26 - x18
    let x28 = x27 * x19
    let x29 = x28 + x20
    let x30 = x29 - x21
    let x31 = x30 * x22
    let x32 = x31 + x23
    let x33 = x32 - x24
    let x34 = x33 * x25
    let x35 = x34 + x26
    let x36 = x35 - x27
    let x37 = x36 * x28
    let x38 = x37 + x29
    let x39 = x38 - x30
    let x40 = x39 * x31
    let x41 = x40 + x32
    let x42 = x41 - x33
    let x43 = x42 * x34
    let x44 = x43 + x35
    let x45 = x44 - x36
    let x46 = x45 * x37
    let x47 = x46 + x38
    let x48 = x47 - x39
    let x49 = x48 * x40
    let x50 = x49 + x41
    print(x50)
}

func deeplyNested(value: Int) {
    if value > 0 {
        if value > 10 {
            if value > 20 {
                if value > 30 {
                    if value > 40 {
                        // Too deep!
                        print("very deep")
                    }
                }
            }
        }
    }
}

func highComplexity(a: Int, b: Bool, c: Bool, d: Bool) -> Int {
    if a > 0 {
        if b {
            if c {
                return 1
            } else {
                return 2
            }
        } else if d {
            return 3
        } else {
            return 4
        }
    } else if a < 0 {
        switch a {
        case -1: return 5
        case -2: return 6
        case -3: return 7
        case -4: return 8
        default: return 9
        }
    } else {
        return b && c && d ? 10 : 11
    }
}
