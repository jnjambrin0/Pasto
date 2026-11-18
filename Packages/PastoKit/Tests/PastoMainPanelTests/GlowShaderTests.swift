import Metal
@testable import PastoMainPanel
import Testing

/// The glow's shader is compiled from source when the view is created; one that does not compile
/// only shows as a glow that never appears.
struct GlowShaderTests {
    @Test func theShaderCompilesAndHasBothFunctions() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let library = try await device.makeLibrary(source: GlowShaderSource.code, options: nil)
        #expect(library.makeFunction(name: GlowShaderSource.vertexFunction) != nil)
        #expect(library.makeFunction(name: GlowShaderSource.fragmentFunction) != nil)
    }
}
