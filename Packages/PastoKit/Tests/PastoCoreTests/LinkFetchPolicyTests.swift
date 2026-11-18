import Foundation
@testable import PastoCore
import Testing

struct LinkFetchPolicyTests {
    @Test(arguments: [
        "https://ejemplo.com",
        "http://www.apple.com/es/",
        "HTTPS://Ejemplo.COM./a?b=c",
        "https://8.8.8.8/",
        "https://[2606:4700::1111]/",
        "https://example.co.uk:8443/x",
    ])
    func publicWebPagesAreAsked(address: String) throws {
        #expect(LinkFetchPolicy.allowsFetching(try #require(URL(string: address))))
    }

    @Test(arguments: [
        // Not a web page.
        "ftp://ejemplo.com/a",
        "file:///etc/passwd",
        "smb://servidor/compartido",
        "vnc://ejemplo.com",
        "miapp://ejemplo.com/accion",
        "javascript://ejemplo.com",
        // This Mac and the local network, by name.
        "http://localhost:8080/admin",
        "http://LOCALHOST./",
        "http://app.localhost/",
        "http://impresora.local/",
        "http://nas.home.arpa/",
        "http://router.lan/",
        "http://wiki.internal/",
        "http://intranet/",
        // …and by address.
        "http://127.0.0.1/",
        "http://127.1.2.3:631/",
        "http://0.0.0.0/",
        "http://10.0.0.1/",
        "http://172.16.5.4/",
        "http://172.31.255.255/",
        "http://192.168.1.1/reboot",
        "http://169.254.169.254/latest/meta-data",
        "http://100.64.0.1/",
        "http://224.0.0.1/",
        "http://255.255.255.255/",
        "http://[::1]/",
        "http://[::]/",
        "http://[fe80::1]/",
        "http://[fd12:3456::1]/",
        "http://[::ffff:192.168.1.1]/",
        "http://[::ffff:7f00:1]/",
        "http://[ff02::1]/",
    ])
    func everythingElseIsNot(address: String) throws {
        #expect(!LinkFetchPolicy.allowsFetching(try #require(URL(string: address))))
    }

    @Test func addressesOutsideThePrivateRangesArePublic() throws {
        #expect(try #require(IPAddress("172.32.0.1")).isPublic)
        #expect(try #require(IPAddress("100.128.0.1")).isPublic)
        #expect(try #require(IPAddress("192.169.0.1")).isPublic)
        #expect(try #require(IPAddress("::ffff:8.8.8.8")).isPublic)
        #expect(try #require(IPAddress("64:ff9b::808:808")).isPublic)
        #expect(try !#require(IPAddress("64:ff9b::a00:1")).isPublic)
        #expect(IPAddress("ejemplo.com") == nil)
    }

    @Test func aConnectionCountsByTheAddressItReached() {
        #expect(LinkFetchPolicy.allowsConnection(to: "93.184.216.34", throughProxy: false))
        #expect(LinkFetchPolicy.allowsConnection(to: "2606:2800:220:1:248:1893:25c8:1946", throughProxy: false))
        #expect(!LinkFetchPolicy.allowsConnection(to: "127.0.0.1", throughProxy: false))
        #expect(!LinkFetchPolicy.allowsConnection(to: "192.168.1.20", throughProxy: false))
        #expect(!LinkFetchPolicy.allowsConnection(to: "fe80::1%en0", throughProxy: false))
        // A proxy the user set up is not the page.
        #expect(LinkFetchPolicy.allowsConnection(to: "10.0.0.8", throughProxy: true))
        #expect(LinkFetchPolicy.allowsConnection(to: nil, throughProxy: false))
    }

    @Test func aNameThatPointsIntoTheMacIsNotAsked() async throws {
        #expect(!(await LinkFetchPolicy.resolvesToPublicAddresses(try #require(URL(string: "http://localhost/")))))
        #expect(!(await LinkFetchPolicy.resolvesToPublicAddresses(try #require(URL(string: "http://127.0.0.1/")))))
        #expect(await LinkFetchPolicy.resolvesToPublicAddresses(try #require(URL(string: "http://8.8.8.8/"))))
    }
}
