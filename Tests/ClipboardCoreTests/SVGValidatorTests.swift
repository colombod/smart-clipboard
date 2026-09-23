import Foundation
import Testing
@testable import ClipboardCore

struct SVGValidatorTests {
    private func svg(_ body: String) -> String {
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 500 260'>" + body + "</svg>"
    }
    @Test func acceptsTracerPathsAndOrdinaryXMLProlog() throws {
        try SVGValidator.validate("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- trace -->" + svg("<path fill='#123abc' transform='translate(10,20)' d='M0 0 C1.5 2 3 4 5 6 L10-2.5 Z'/>"))
    }
    @Test func acceptsSafeModelFeaturesAndInternalResources() throws {
        try SVGValidator.validate(svg("""
        <defs><linearGradient id="shade"><stop offset="0%" stop-color="#fff"/><stop offset="100%" stop-color="blue"/></linearGradient>
        <path id="outline" d="M0 0A10 20 30 0 1 50 60Z"/>
        <filter id="shadow"><feGaussianBlur stdDeviation="2"/><feOffset dx="1" dy="1"/></filter></defs>
        <style>.paint { stroke: black; stroke-width: 1; }.label { fill: navy; }</style>
        <g transform="translate(4 5) scale(2) rotate(30 5 6)"><use href="#outline" class="paint" style="fill: url(#shade); " filter="url(#shadow)"/></g>
        <text x="20" y="80" font-family="Arial, sans-serif">Café &amp; tea</text>
        """))
    }
    @Test func acceptsXlinkInternalUse() throws {
        try SVGValidator.validate("<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' viewBox='0 0 10 10'><defs><circle id='dot' cx='2' cy='2' r='1'/></defs><use xlink:href='#dot'/></svg>")
    }
    @Test(arguments: [
        "<script>alert(1)</script>", "<foreignObject><div>hello</div></foreignObject>",
        "<image href='data:image/png;base64,AAAA'/>", "<image href='https://example.com/a.png'/>",
        "<rect width='5' height='5' onclick='alert(1)'/>",
        "<rect width='5' height='5' fill='url(https://example.com/a.svg)'/>",
        "<use href='file:///tmp/private.svg#x'/>", "<use href='//example.com/x.svg'/>",
        "<use href='&#106;avascript:alert(1)'/>",
        "<style>@import 'https://example.com/x.css';</style>",
        "<style>.x{fill:u\\72l(https://example.com/x)}</style>",
        "<rect style='fill:red;behavior:url(#x)'/>",
        "<animate attributeName='href' to='https://example.com'/>",
        "<table><tr><td>HTML is not SVG</td></tr></table>",
        "<path xmlns='http://www.w3.org/1999/xhtml' d='M0 0L1 1'/>",
        "<?xml-stylesheet href='https://example.com/x.css'?>"
    ])
    func rejectsActiveExternalAndNonVectorContent(_ body: String) {
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(body)) }
    }
    @Test(arguments: [
        "", "<svg/>", "<svg xmlns='http://www.w3.org/2000/svg'/>",
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 -1 1'/>",
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1e309 1'/>",
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><path></svg>",
        "<!DOCTYPE svg [<!ENTITY x 'expanded'>]><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><text>&x;</text></svg>",
        "<!DOCTYPE svg SYSTEM 'file:///tmp/private'><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'/>"
    ])
    func rejectsMalformedDocumentsAndEntities(_ value: String) {
        #expect(throws: (any Error).self) { try SVGValidator.validate(value) }
    }
    @Test(arguments: [
        "<path d='MNaN 1L2 3'/>", "<path d='M0 0L1e309 2'/>", "<path d='L0 0'/>",
        "<path d='M0 0C1 2'/>", "<path d='M0 0A1 1 0 2 0 3 4'/>",
        "<circle cx='Infinity' cy='1' r='2'/>", "<circle cx='1' cy='1' r='-2'/>",
        "<rect width='1e309' height='1'/>", "<g transform='matrix(1 0 0 1 1e309 0)'/>",
        "<g transform='translate(1) unknown(4)'/>", "<g transform='scale(1e6)'/>",
        "<polyline points='1 2 3'/>", "<path d='M0 0L1 1' stroke-dasharray='1e309 2'/>",
        "<filter id='blur'><feGaussianBlur stdDeviation='10000'/></filter>"
    ])
    func rejectsInvalidOrUnboundedGeometry(_ value: String) {
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(value)) }
    }
    @Test(arguments: [
        "<use href='#missing'/>",
        "<g id='a'><use href='#a'/></g>",
        "<defs><g id='a'><use href='#b'/></g><g id='b'><use href='#a'/></g></defs><use href='#a'/>",
        "<rect id='same'/><circle id='same'/>"
    ])
    func rejectsBrokenOrCyclicReferences(_ value: String) {
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(value)) }
    }
    @Test(arguments: [false, true])
    func boundsReferenceDepthRegardlessOfDefinitionOrder(_ reverse: Bool) throws {
        func chain(_ count: Int) -> String {
            var definitions = ["<g id='g0'><rect width='1' height='1'/></g>"]
            for index in 1..<count {
                definitions.append("<g id='g\(index)'><use href='#g\(index - 1)'/></g>")
            }
            if reverse { definitions.reverse() }
            return svg("<defs>" + definitions.joined() + "</defs><use href='#g\(count - 1)'/>")
        }
        try SVGValidator.validate(chain(16))
        #expect(throws: (any Error).self) { try SVGValidator.validate(chain(21)) }
    }
    @Test(arguments: [
        "<style>.loop { fill:url(#tile); }</style><defs><pattern id='tile' width='10' height='10'><rect class='loop' width='10' height='10'/></pattern></defs><rect class='loop' width='10' height='10'/>",
        "<defs><linearGradient id='shade'><stop offset='0' stop-color='blue'/></linearGradient></defs><style>.paint { fill: URL( '#shade' ); }</style><rect class='paint' width='10' height='10'/>",
        "<defs><pattern id='tile' width='10' height='10'><rect style='fill:url(#tile)' width='10' height='10'/></pattern></defs><rect fill='url(#tile)' width='10' height='10'/>"
    ])
    func rejectsStylesheetResourcesAndInlineResourceCycles(_ value: String) {
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(value)) }
    }
    @Test func boundsDepthAndPathCountAndBytes() {
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(String(repeating: "<g>", count: 65) + String(repeating: "</g>", count: 65))) }
        #expect(throws: (any Error).self) { try SVGValidator.validate(svg(String(repeating: "<path d='M0 0L1 1'/>", count: SVGValidator.maximumPaths + 1))) }
        #expect(throws: (any Error).self) { try SVGValidator.validate(String(repeating: " ", count: SVGValidator.maximumBytes + 1)) }
    }
    @Test func harmlessCommentsAndDescriptionsRemainUsable() throws {
        try SVGValidator.validate(svg("<!-- This text mentions <!DOCTYPE without declaring one -->\n<desc>&lt;script&gt; is a description, not executable code.</desc><path d='M0 0L10 10'/>") )
    }
    @Test func aiEnvelopeUsesTheSameSVGValidationGate() throws {
        let invalid = try JSONSerialization.data(withJSONObject: ["format": "svg", "content": svg("<foreignObject/>")])
        #expect(throws: (any Error).self) { try ConversionProtocol.decode(String(decoding: invalid, as: UTF8.self), requested: .auto) }
        let valid = try JSONSerialization.data(withJSONObject: ["format": "svg", "content": svg("<circle cx='4' cy='5' r='2'/>")])
        #expect(try ConversionProtocol.decode(String(decoding: valid, as: UTF8.self), requested: .svg).format == .svg)
    }
}
