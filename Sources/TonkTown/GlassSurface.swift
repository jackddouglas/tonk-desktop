import SwiftUI

/// Glass belongs to the control layer; transcripts and hosted space content stay opaque.
struct GlassSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var radius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(
        Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
    } else if #available(macOS 26.0, *) {
      content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
    } else {
      content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
    }
  }
}

extension View {
  func controlSurface(radius: CGFloat = 20) -> some View {
    modifier(GlassSurface(radius: radius))
  }
}

struct NativeControlStyle: ViewModifier {
  var prominent = false
  var circular = false

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        content.buttonStyle(.glassProminent).buttonBorderShape(circular ? .circle : .capsule)
      } else {
        content.buttonStyle(.glass).buttonBorderShape(circular ? .circle : .capsule)
      }
    } else if prominent {
      content.buttonStyle(.borderedProminent)
    } else {
      content.buttonStyle(.bordered)
    }
  }
}

extension View {
  func nativeControl(prominent: Bool = false, circular: Bool = false) -> some View {
    modifier(NativeControlStyle(prominent: prominent, circular: circular))
  }
}
