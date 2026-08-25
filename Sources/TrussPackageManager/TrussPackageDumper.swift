import Foundation
import TrussCore

public enum TrussPackageDumper {
    public static func dump(_ interface: ModuleInterface) -> String {
        ModuleInterfaceDumper().dump(interface)
    }
}
