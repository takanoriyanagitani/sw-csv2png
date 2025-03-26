import class CoreGraphics.CGColorSpace
import func CoreGraphics.CGColorSpaceCreateDeviceRGB
import struct CoreGraphics.CGSize
import class CoreImage.CIContext
import struct CoreImage.CIFormat
import class CoreImage.CIImage
import struct Foundation.Data
import class Foundation.ProcessInfo
import struct Foundation.URL

enum CsvToPngErr: Error {
  case unexpectedWidth(String)
  case invalidArgument(String)
  case unimplemented(String)
}

typealias Rgba8 = (UInt8, UInt8, UInt8, UInt8)

typealias LineToRgba8 = (String) -> [Rgba8]

func LineToRgbaNew8(width: Int, separator: String = ",") -> LineToRgba8 {
  return {
    let line: String = $0
    let splited = line.split(separator: separator)

    var ret: [Rgba8] = Array(repeating: (0, 0, 0, 0), count: width)
    ret.removeAll(keepingCapacity: true)

    let es = splited.enumerated()

    var rgba: [UInt8] = [0, 0, 0, 0]
    for pair in es {
      let (ix, val) = pair
      let ov: UInt8? = UInt8(val)
      guard let v = ov else {
        return ret
      }

      let m: Int = ix & 3
      rgba[m] = v

      if 3 == m {
        ret.append(
          (
            rgba[0],
            rgba[1],
            rgba[2],
            rgba[3]
          ))
      }
    }

    return ret
  }
}

typealias Lines = () -> String?

func stdin2lines() -> Lines {
  return {
    return readLine()
  }
}

typealias LinesToRgbaData8 = (@escaping Lines) -> Result<Data, Error>

struct LinesToRgbaDataViii {
  public let line2rgba8: LineToRgba8
  public let width: Int
  public let height: Int

  public func bytesPerRow() -> Int { return 4 * self.width }

  public func format() -> CIFormat { .RGBA8 }
  public func color() -> CGColorSpace { CGColorSpaceCreateDeviceRGB() }

  public func ToLinesToRgbaData8() -> LinesToRgbaData8 {
    return {
      let lines: Lines = $0
      var dat: Data = Data(capacity: self.height * self.bytesPerRow())
      while true {
        let oline: String? = lines()
        guard let line = oline else {
          return .success(dat)
        }

        let parsed: [Rgba8] = self.line2rgba8(line)
        guard parsed.count == self.width else {
          return .failure(CsvToPngErr.unexpectedWidth("\( parsed.count )"))
        }

        for p in parsed {
          let r: UInt8 = p.0
          let g: UInt8 = p.1
          let b: UInt8 = p.2
          let a: UInt8 = p.3

          dat.append(contentsOf: [r, g, b, a])
        }
      }
    }
  }
}

typealias RgbaDataToImage8 = (Data) -> Result<CIImage, Error>

struct RgbaDataToImageViii {
  public let width: Int
  public let height: Int

  public func bytesPerRow() -> Int { return 4 * self.width }
  public func size() -> CGSize {
    return CGSize(
      width: self.width,
      height: self.height
    )
  }

  public func format() -> CIFormat { .RGBA8 }
  public func color() -> CGColorSpace { CGColorSpaceCreateDeviceRGB() }

  public func ToRgbaDataToImage8() -> RgbaDataToImage8 {
    return {
      let dat: Data = $0
      return .success(
        CIImage(
          bitmapData: dat,
          bytesPerRow: self.bytesPerRow(),
          size: self.size(),
          format: self.format(),
          colorSpace: self.color()
        ))
    }
  }
}

typealias LinesToImage = (@escaping Lines) -> Result<CIImage, Error>

struct LinesToImg {
  public let lines2rgba8: LinesToRgbaData8
  public let rgba2img8: RgbaDataToImage8

  public func ToLinesToImage() -> LinesToImage {
    return {
      let lines: Lines = $0
      let rdat: Result<Data, Error> = self.lines2rgba8(lines)
      return rdat.flatMap {
        let dat: Data = $0
        return self.rgba2img8(dat)
      }
    }
  }
}

typealias ImageWriterPng = (CIImage) -> Result<Void, Error>
typealias ImageWriterPngFs = (URL) -> ImageWriterPng

func ImageToUrlPngRgba8(_ url: URL) -> ImageWriterPng {
  let ctx: CIContext = CIContext()
  return {
    let img: CIImage = $0
    return Result(catching: {
      try ctx.writePNGRepresentation(
        of: img,
        to: url,
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        options: [:]
      )
    })
  }
}

func envValByKey(_ key: String) -> Result<String, Error> {
  let values: [String: String] = ProcessInfo.processInfo.environment
  let oval: String? = values[key]
  guard let val = oval else {
    return .failure(CsvToPngErr.invalidArgument("env var \( key ) missing"))
  }
  return .success(val)
}

func str2int(_ s: String) -> Result<Int, Error> {
  let oint: Int? = Int(s)
  guard let i = oint else {
    return .failure(CsvToPngErr.invalidArgument("invalid int: \( s )"))
  }
  return .success(i)
}

func Compose<T, U, V>(
  _ f: @escaping (T) -> Result<U, Error>,
  _ g: @escaping (U) -> Result<V, Error>
) -> (T) -> Result<V, Error> {
  return {
    let t: T = $0
    let ru: Result<U, Error> = f(t)
    return ru.flatMap {
      let u: U = $0
      return g(u)
    }
  }
}

func pngWidth() -> Result<Int, Error> {
  return Compose(envValByKey, str2int)("ENV_PNG_WIDTH")
}

func pngHeight() -> Result<Int, Error> {
  return Compose(envValByKey, str2int)("ENV_PNG_HEIGHT")
}

struct PngSize {
  public let width: Int
  public let height: Int

  public func ToLineToRgba8(separator: String = ",") -> LineToRgba8 {
    LineToRgbaNew8(
      width: self.width,
      separator: separator
    )
  }

  public func ToLinesToRgbaData8(separator: String = ",") -> LinesToRgbaData8 {
    let l2r: LineToRgba8 = self.ToLineToRgba8(separator: separator)
    let l2rd: LinesToRgbaDataViii = LinesToRgbaDataViii(
      line2rgba8: l2r,
      width: self.width,
      height: self.height
    )
    return l2rd.ToLinesToRgbaData8()
  }

  public func ToRgbaDatToImg8() -> RgbaDataToImage8 {
    return RgbaDataToImageViii(
      width: self.width,
      height: self.height
    ).ToRgbaDataToImage8()
  }

  public func ToLinesToImg8(separator: String = ",") -> LinesToImage {
    return LinesToImg(
      lines2rgba8: self.ToLinesToRgbaData8(separator: separator),
      rgba2img8: self.ToRgbaDatToImg8()
    ).ToLinesToImage()
  }
}

func pngSize() -> Result<PngSize, Error> {
  let rw: Result<Int, Error> = pngWidth()
  let rh: Result<Int, Error> = pngHeight()
  return rw.flatMap {
    let w: Int = $0
    return rh.map {
      let h: Int = $0
      return PngSize(width: w, height: h)
    }
  }
}

func outputPngName() -> Result<String, Error> { envValByKey("ENV_OUT_PNG_NAME") }

func outputPngUrl() -> Result<URL, Error> {
  let rname: Result<String, _> = outputPngName()
  return rname.map {
    let name: String = $0
    return URL(fileURLWithPath: name)
  }
}

func sub(separator: String = ",") -> Result<Void, Error> {
  let lines: Lines = stdin2lines()

  let img2fs: ImageWriterPngFs = ImageToUrlPngRgba8

  let psize: Result<PngSize, Error> = pngSize()
  let lines2img: Result<LinesToImage, Error> = psize.map {
    let ps: PngSize = $0
    return ps.ToLinesToImg8(separator: separator)
  }

  let rimg: Result<CIImage, Error> = lines2img.flatMap {
    let l2i: LinesToImage = $0
    return l2i(lines)
  }

  let rpurl: Result<URL, _> = outputPngUrl()
  let wimg: Result<ImageWriterPng, _> = rpurl.map {
    let u: URL = $0
    return img2fs(u)
  }

  return wimg.flatMap {
    let wtr: ImageWriterPng = $0
    return rimg.flatMap {
      let i: CIImage = $0
      return wtr(i)
    }
  }
}

@main
struct CsvToPng {
  static func main() {
    let r: Result<_, _> = sub()
    do {
      try r.get()
    } catch {
      print("\( error )")
    }
  }
}
