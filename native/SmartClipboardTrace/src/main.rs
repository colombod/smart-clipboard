use image::{codecs::png::PngDecoder, DynamicImage, ImageDecoder};
use std::ffi::OsString;
use std::fmt::{self, Write as FmtWrite};
use std::fs::{self, OpenOptions};
use std::io::{Cursor, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;

const MAX_INPUT: u64 = 64 * 1024 * 1024;
const MAX_PIXELS: u64 = 16_000_000;
const MAX_SIDE: u32 = 8000;
const MAX_SVG: usize = 16 * 1024 * 1024;
const MAX_PATHS: usize = 100_000;
const VERSION_JSON: &str = r#"{"name":"SmartClipboardTrace","helperVersion":"1.0.0","engine":"vtracer","version":"0.6.5","protocolVersion":1}"#;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Preset { Photo, Logo, LineArt }
#[derive(Clone, Copy, Debug, PartialEq)]
enum Detail { Balanced, Detailed }
#[derive(Debug)]
struct Request { input: PathBuf, output: PathBuf, preset: Preset, detail: Detail }

fn arguments(args: Vec<OsString>) -> Result<Option<Request>, &'static str> {
    if args == [OsString::from("--version")] { return Ok(None); }
    if args.len() != 8 { return Err("Expected --input PNG --output SVG --preset photo|logo|line-art --detail balanced|detailed."); }
    let (mut input, mut output, mut preset, mut detail) = (None, None, None, None);
    for pair in args.chunks_exact(2) {
        match pair[0].to_str() {
            Some("--input") if input.is_none() => input = Some(PathBuf::from(&pair[1])),
            Some("--output") if output.is_none() => output = Some(PathBuf::from(&pair[1])),
            Some("--preset") if preset.is_none() => preset = Some(match pair[1].to_str() {
                Some("photo") => Preset::Photo, Some("logo") => Preset::Logo,
                Some("line-art") => Preset::LineArt, _ => return Err("Unknown tracing preset."),
            }),
            Some("--detail") if detail.is_none() => detail = Some(match pair[1].to_str() {
                Some("balanced") => Detail::Balanced, Some("detailed") => Detail::Detailed,
                _ => return Err("Unknown tracing detail."),
            }),
            _ => return Err("Unknown or duplicate argument."),
        }
    }
    let request = Request { input: input.ok_or("Missing input.")?, output: output.ok_or("Missing output.")?,
        preset: preset.ok_or("Missing preset.")?, detail: detail.ok_or("Missing detail.")? };
    if !request.input.is_absolute() || !request.output.is_absolute() { return Err("Input and output must be absolute paths."); }
    if request.input == request.output { return Err("Input and output must differ."); }
    Ok(Some(request))
}

fn dimensions(width: u32, height: u32) -> Result<(), &'static str> {
    if width == 0 || height == 0 || width > MAX_SIDE || height > MAX_SIDE || u64::from(width) * u64::from(height) > MAX_PIXELS {
        return Err("Image exceeds the 8000-pixel side or 16000000-pixel area limit.");
    }
    Ok(())
}

fn decode(bytes: &[u8]) -> Result<vtracer::ColorImage, &'static str> {
    // Check the fixed PNG header before the decoder can allocate image buffers.
    if bytes.len() < 33 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" || &bytes[12..16] != b"IHDR" || bytes[8..12] != [0, 0, 0, 13] {
        return Err("Input is not a PNG image.");
    }
    let width = u32::from_be_bytes(bytes[16..20].try_into().unwrap());
    let height = u32::from_be_bytes(bytes[20..24].try_into().unwrap());
    dimensions(width, height)?;
    let decoder = PngDecoder::new(Cursor::new(bytes)).map_err(|_| "PNG header is invalid.")?;
    if decoder.dimensions() != (width, height) { return Err("PNG dimensions are inconsistent."); }
    let rgba = DynamicImage::from_decoder(decoder).map_err(|_| "PNG image could not be decoded.")?.to_rgba8();
    Ok(vtracer::ColorImage { pixels: rgba.into_raw(), width: width as usize, height: height as usize })
}

fn config(preset: Preset, detail: Detail) -> vtracer::Config {
    // Photo values reproduce the evaluated Python binding's explicit settings;
    // they deliberately do not use the upstream Photo preset's different values.
    let mut result = match preset {
        Preset::Photo => vtracer::Config::default(),
        Preset::Logo => vtracer::Config::from_preset(vtracer::Preset::Poster),
        Preset::LineArt => vtracer::Config::from_preset(vtracer::Preset::Bw),
    };
    result.path_precision = Some(3);
    if detail == Detail::Detailed {
        result.filter_speckle = 2;
        result.color_precision = 8;
        result.layer_difference = 4;
    }
    result
}

struct BoundedText { value: String, limit: usize }
impl fmt::Write for BoundedText {
    fn write_str(&mut self, text: &str) -> fmt::Result {
        if text.len() > self.limit.saturating_sub(self.value.len()) { return Err(fmt::Error); }
        self.value.push_str(text); Ok(())
    }
}
fn serialize(svg: &vtracer::SvgFile) -> Result<String, &'static str> {
    if svg.paths.is_empty() { return Err("No visible paths were found."); }
    if svg.paths.len() > MAX_PATHS { return Err("Trace exceeds the 100000-path limit. Try a smaller image or balanced detail."); }
    let mut text = BoundedText { value: String::new(), limit: MAX_SVG - 128 };
    write!(&mut text, "{svg}").map_err(|_| "Trace exceeds the 16 MiB SVG limit. Try a smaller image or balanced detail.")?;
    let position = text.value.find("<svg ").ok_or("Engine returned an invalid SVG.")?;
    text.value.insert_str(position + 5, &format!("viewBox=\"0 0 {} {}\" ", svg.width, svg.height));
    Ok(text.value)
}

fn trace(request: Request) -> Result<(), &'static str> {
    let mut input = OpenOptions::new().read(true).custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(&request.input).map_err(|_| "Cannot open the input PNG.")?;
    let metadata = input.metadata().map_err(|_| "Cannot inspect the input PNG.")?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_INPUT { return Err("Input must be a nonempty regular PNG file at most 64 MiB."); }
    // Never overwrite a caller's file or follow an output symlink.
    if fs::symlink_metadata(&request.output).is_ok() { return Err("Output already exists."); }
    let mut bytes = Vec::new();
    (&mut input).take(MAX_INPUT + 1).read_to_end(&mut bytes).map_err(|_| "Cannot read the input PNG.")?;
    if bytes.len() as u64 > MAX_INPUT { return Err("Input exceeds 64 MiB."); }
    let mut image = decode(&bytes)?;
    drop(bytes);
    if request.preset == Preset::LineArt {
        // The upstream binary preset thresholds red only. Supply luminance so
        // dark coloured strokes remain visible; transparent pixels become white.
        for pixel in image.pixels.chunks_exact_mut(4) {
            let luminance = (2126 * u32::from(pixel[0]) + 7152 * u32::from(pixel[1]) + 722 * u32::from(pixel[2])) / 10000;
            let value = ((luminance * u32::from(pixel[3]) + 255 * (255 - u32::from(pixel[3]))) / 255) as u8;
            pixel.copy_from_slice(&[value, value, value, 255]);
        }
    }
    let svg = vtracer::convert(image, config(request.preset, request.detail)).map_err(|_| "The tracing engine could not process this image.")?;
    let text = serialize(&svg)?;
    let mut output = OpenOptions::new().write(true).create_new(true).mode(0o600)
        .open(&request.output).map_err(|_| "Cannot create the output SVG.")?;
    if output.write_all(text.as_bytes()).and_then(|_| output.sync_all()).is_err() {
        drop(output); let _ = fs::remove_file(&request.output);
        return Err("Cannot write the output SVG.");
    }
    println!("{{\"engine\":\"vtracer\",\"version\":\"0.6.5\",\"paths\":{},\"bytes\":{},\"width\":{},\"height\":{}}}", svg.paths.len(), text.len(), svg.width, svg.height);
    Ok(())
}

fn resource_limits() -> Result<(), &'static str> {
    // The app supplies a 90-second wall deadline; this also bounds CPU and files
    // if the helper is invoked directly. There is no child process or network API.
    for (resource, maximum) in [(libc::RLIMIT_CPU, 85), (libc::RLIMIT_FSIZE, (MAX_SVG + 1024) as u64)] {
        let limit = libc::rlimit { rlim_cur: maximum as libc::rlim_t, rlim_max: maximum as libc::rlim_t };
        if unsafe { libc::setrlimit(resource, &limit) } != 0 { return Err("Cannot apply tracing resource limits."); }
    }
    Ok(())
}

fn main() {
    std::panic::set_hook(Box::new(|_| eprintln!("Tracing engine stopped unexpectedly.")));
    let outcome = match arguments(std::env::args_os().skip(1).collect()) {
        Ok(None) => { println!("{VERSION_JSON}"); Ok(()) },
        Ok(Some(request)) => resource_limits().and_then(|_| trace(request)),
        Err(error) => Err(error),
    };
    if let Err(error) = outcome { eprintln!("{error}"); std::process::exit(1); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(items: &[&str]) -> Vec<OsString> { items.iter().map(OsString::from).collect() }
    #[test] fn strict_arguments() {
        assert!(arguments(args(&["--version"])).unwrap().is_none());
        assert!(arguments(args(&["--version", "--input", "/tmp/x"])).is_err());
        assert!(arguments(args(&["--input", "/tmp/i", "--output", "/tmp/o", "--preset", "photo", "--detail", "detailed"])).unwrap().is_some());
        assert!(arguments(args(&["--input", "/tmp/i", "--input", "/tmp/o", "--preset", "photo", "--detail", "detailed"])).is_err());
        assert!(arguments(args(&["--input", "relative", "--output", "/tmp/o", "--preset", "photo", "--detail", "detailed"])).is_err());
    }
    #[test] fn rejects_oversize_header_without_decoding() {
        let mut header = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        header.extend_from_slice(&u32::MAX.to_be_bytes()); header.extend_from_slice(&1u32.to_be_bytes()); header.resize(33, 0);
        assert!(decode(&header).err().unwrap().contains("limit"));
        assert!(dimensions(8000, 2000).is_ok()); assert!(dimensions(8000, 2001).is_err());
        assert!(dimensions(0, 10).is_err()); assert!(decode(b"not png").is_err());
    }
    #[test] fn bounded_output() {
        let mut output = BoundedText { value: String::new(), limit: 3 };
        assert!(write!(&mut output, "abc").is_ok()); assert!(write!(&mut output, "d").is_err());
        assert_eq!(output.value, "abc");
    }
    #[test] fn study_photo_settings_preserved() {
        let balanced = config(Preset::Photo, Detail::Balanced);
        let detailed = config(Preset::Photo, Detail::Detailed);
        assert_eq!((balanced.filter_speckle, balanced.color_precision, balanced.layer_difference), (4, 6, 16));
        assert_eq!((detailed.filter_speckle, detailed.color_precision, detailed.layer_difference), (2, 8, 4));
    }
}
