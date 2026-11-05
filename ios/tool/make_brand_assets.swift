// Regenerates the app icon set, launch image and the in-app logo mark from the
// Tevel Invoice logo. Usage (from repo root):
//   swift ios/tool/make_brand_assets.swift <path/to/tevelinvoicelogo.png>
// The asterisk mark is cropped automatically (the green pixels left of the wordmark)
// and drawn on charcoal #1D1D20. Icons are written WITHOUT an alpha channel.
import AppKit
import CoreGraphics
import Foundation

let charcoal = CGColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x20 / 255.0, alpha: 1)

func loadImage(_ path: String) -> CGImage {
  guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
  return img
}

/// Bounding box of "green" pixels (the asterisk), in top-left image coordinates.
func markRect(_ img: CGImage) -> CGRect {
  let w = img.width, h = img.height
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  var minX = w, minY = h, maxX = 0, maxY = 0
  for y in 0..<h {
    for x in 0..<w {
      let i = (y * w + x) * 4
      let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2]), a = Int(px[i + 3])
      if a > 128 && g > 120 && g - r > 60 && g - b > 10 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
  }
  precondition(maxX > minX, "no green mark found")
  // CGContext memory row 0 is the top row of the image.
  return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// Mark with its white background removed (white → transparent, keeps the green).
func cleanMark(_ img: CGImage, _ r: CGRect) -> CGImage {
  let crop = img.cropping(to: r)!
  let w = crop.width, h = crop.height
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))  // source may be transparent
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
  for i in stride(from: 0, to: px.count, by: 4) {
    let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
    // Un-mix from the white background: the mark's red channel is ~0, so 255-min = coverage.
    let a = max(0, min(1, (255 - min(r, g, b)) / 235.0))
    // Premultiplied colour = observed - (1 - a) * white.
    func un(_ c: Double) -> UInt8 { UInt8(max(0, min(255 * a, c - (1 - a) * 255))) }
    px[i] = un(r); px[i + 1] = un(g); px[i + 2] = un(b); px[i + 3] = UInt8(a * 255)
  }
  return ctx.makeImage()!
}

func render(_ mark: CGImage, size: Int, markFraction: Double, background: CGColor?) -> CGImage {
  let info = background == nil ? CGImageAlphaInfo.premultipliedLast.rawValue
                               : CGImageAlphaInfo.noneSkipLast.rawValue
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
  ctx.interpolationQuality = .high
  if let bg = background { ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
  let side = Double(size) * markFraction
  let aspect = Double(mark.width) / Double(mark.height)
  let mw = aspect >= 1 ? side : side * aspect, mh = aspect >= 1 ? side / aspect : side
  ctx.draw(mark, in: CGRect(x: (Double(size) - mw) / 2, y: (Double(size) - mh) / 2, width: mw, height: mh))
  return ctx.makeImage()!
}

func writePNG(_ img: CGImage, _ path: String) {
  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, img, nil)
  precondition(CGImageDestinationFinalize(dest), "write failed \(path)")
}

let args = CommandLine.arguments
guard args.count == 2 else { fatalError("usage: make_brand_assets.swift <logo.png>") }
let logo = loadImage(args[1])
let mark = cleanMark(logo, markRect(logo))

// 1) App icons — every file listed in AppIcon.appiconset/Contents.json.
let iconDir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let contents = try! JSONSerialization.jsonObject(
  with: Data(contentsOf: URL(fileURLWithPath: iconDir + "/Contents.json"))) as! [String: Any]
for entry in contents["images"] as! [[String: Any]] {
  guard let file = entry["filename"] as? String else { continue }
  let pt = Double((entry["size"] as! String).split(separator: "x")[0])!
  let scale = Double((entry["scale"] as! String).dropLast())!
  writePNG(render(mark, size: Int((pt * scale).rounded()), markFraction: 0.62, background: charcoal),
           iconDir + "/" + file)
}

// 2) Launch image (mark only, transparent; the storyboard paints the charcoal background).
let launchDir = "ios/Runner/Assets.xcassets/LaunchImage.imageset"
for (scale, file) in [(1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")] {
  writePNG(render(mark, size: 96 * scale, markFraction: 1, background: nil), launchDir + "/" + file)
}

// 3) In-app mark for Flutter (transparent, 512px).
try? FileManager.default.createDirectory(atPath: "assets/brand", withIntermediateDirectories: true)
writePNG(render(mark, size: 512, markFraction: 1, background: nil), "assets/brand/tevel_mark.png")
print("brand assets written")
