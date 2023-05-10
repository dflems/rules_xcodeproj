import CustomDump
import XcodeProj
import XCTest

@testable import generator

final class CreateXCUserDataTests: XCTestCase {
    func test_basic() throws {
        // Arrange
        
        let userName = "userName"
        let customSchemes = [
            XCScheme(name: "User Defined B", lastUpgradeVersion: nil, version: nil),
            XCScheme(name: "User Defined A", lastUpgradeVersion: nil, version: nil)
        ]
        let autogeneratedSchemes = [
            XCScheme(name: "Non Top Level A", lastUpgradeVersion: nil, version: nil),
            XCScheme(name: "Top Level B", lastUpgradeVersion: nil, version: nil),
            XCScheme(name: "Top Level A", lastUpgradeVersion: nil, version: nil),
            XCScheme(name: "Non Top Level B", lastUpgradeVersion: nil, version: nil)
        ]
        let targets = [
            PBXTarget(name: "Top Level A", productType: .application),
            PBXTarget(name: "Top Level B", productType: .unitTestBundle),
            PBXTarget(name: "Non Top Level A"),
            PBXTarget(name: "Non Top Level B")
        ]
        
        let expectedUserData = XCUserData(
            userName: userName,
            schemes: [],
            schemeManagement: XCSchemeManagement(
                schemeUserState: [
                    XCSchemeManagement.UserStateScheme(
                        name: "User Defined B.xcscheme",
                        shared: true,
                        orderHint: 0,
                        isShown: true
                    ),
                    XCSchemeManagement.UserStateScheme(
                        name: "User Defined A.xcscheme",
                        shared: true,
                        orderHint: 1,
                        isShown: true
                    ),
                    XCSchemeManagement.UserStateScheme(
                        name: "Top Level A.xcscheme",
                        shared: true,
                        orderHint: 2,
                        isShown: true
                    ),
                    XCSchemeManagement.UserStateScheme(
                        name: "Top Level B.xcscheme",
                        shared: true,
                        orderHint: 3,
                        isShown: true
                    ),
                    XCSchemeManagement.UserStateScheme(
                        name: "Non Top Level A.xcscheme",
                        shared: true,
                        orderHint: 4,
                        isShown: true
                    ),
                    XCSchemeManagement.UserStateScheme(
                        name: "Non Top Level B.xcscheme",
                        shared: true,
                        orderHint: 5,
                        isShown: true
                    )
                ]
            )
        )

        // Act

        let userData = Generator.createXCUserData(
            userName: userName,
            schemes: customSchemes,
            autogeneratedSchemes: autogeneratedSchemes,
            targets: targets
        )

        // Assert

        XCTAssertNoDifference(userData, expectedUserData)
    }
}