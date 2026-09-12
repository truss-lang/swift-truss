import Testing
import TrussTIRGen

@Suite struct VirtualMethodTests {
    @Test func classMethodCallDispatchesThroughVTable() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak() { return }
            }
            class Dog: Animal {
                func bark() { return }
            }
            func ping(d: Dog) {
                d.bark()
            }
            """
        )
        let lines = tir.components(separatedBy: "\n")
        let method = try #require(lines.first { $0.contains("= virtualmethod") })
        try #require(method.contains("Dog#1.1"))
        try #require(!method.contains(","))
        let name = try #require(
            method.components(separatedBy: " = virtualmethod").first?
                .components(separatedBy: " ").last
        )
        try #require(lines.contains { $0.contains("call void " + name + "(") })
    }

    @Test func subclassInheritsSuperclassSlots() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak() { return }
            }
            class Dog: Animal {
                func bark() { return }
            }
            func ping(d: Dog) {
                d.bark()
            }
            """
        )
        let dog = try #require(
            tir.components(separatedBy: "\n").first { $0.contains("Dog = vtable [") }
        )
        try #require(dog.contains("Animal_5speak"))
        try #require(dog.contains("Dog_4bark"))
        #expect(slotIndex(of: "speak", in: dog) == 0)
        #expect(slotIndex(of: "bark", in: dog) == 1)
    }

    @Test func overrideReusesSuperclassSlot() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak() { return }
            }
            class Dog: Animal {
                func speak() { return }
                func bark() { return }
            }
            func ping(a: Animal, d: Dog) {
                a.speak()
                d.speak()
            }
            """
        )
        let lines = tir.components(separatedBy: "\n")
        let animal = try #require(lines.first { $0.contains("Animal = vtable [") })
        try #require(animal.contains("Animal_5speak"))
        try #require(!animal.contains("bark"))
        let dog = try #require(lines.first { $0.contains("Dog = vtable [") })
        try #require(dog.contains("Dog_5speak"))
        let animalSlot = try #require(slotIndex(of: "speak", in: animal))
        let dogSlot = try #require(slotIndex(of: "speak", in: dog))
        #expect(animalSlot == dogSlot)
        try #require(slotIndex(of: "bark", in: dog) != nil)
    }

    @Test func voidMethodCallHasNoResult() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak() { return }
            }
            func ping(a: Animal) {
                a.speak()
            }
            """
        )
        let call = try #require(
            tir.components(separatedBy: "\n").first { $0.contains("call void") }
        )
        try #require(!call.contains("= call"))
    }

    @Test func finalMethodIsNotInVTable() throws {
        let tir = dumpTIR(
            """
            class Animal {
                func speak() { return }
                final func jump() { return }
            }
            func ping(a: Animal) { return }
            """
        )
        let line = try #require(
            tir.components(separatedBy: "\n").first { $0.contains("Animal = vtable [") }
        )
        try #require(line.contains("speak"))
        #expect(!line.contains("jump"))
    }

    private func slotIndex(of name: String, in vtableLine: String) -> Int? {
        for entry in vtableLine.components(separatedBy: ", ") {
            let parts = entry.components(separatedBy: ": ")
            guard parts.count == 2, parts[1].hasPrefix(name) else { continue }
            return Int(parts[0].components(separatedBy: " ").last ?? "")
        }
        return nil
    }
}
