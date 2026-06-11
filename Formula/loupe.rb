class Loupe < Formula
  desc "CLI giving LLM agents runtime UI context from running iOS Simulator apps"
  homepage "https://github.com/heoblitz/Loupe"
  url "https://github.com/heoblitz/Loupe/archive/refs/tags/v0.1.6.tar.gz"
  sha256 "2ec9a41e9e6475c02f33b80df9e1634b0385471b50c5d7bac64fd4744bc8c216"
  license "MIT"
  head "https://github.com/heoblitz/Loupe.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  def install
    system "swift", "build",
      "--configuration", "release",
      "--disable-sandbox",
      "--product", "loupe"

    bin.install ".build/release/loupe"
    (pkgshare/"skills").install "skills/loupe" => "loupe"

    simulator_triple = Hardware::CPU.arm? ? "arm64-apple-ios15.0-simulator" : "x86_64-apple-ios15.0-simulator"
    simulator_sdk = Utils.safe_popen_read("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path").strip
    injector_scratch = buildpath/".build/homebrew-loupe-injector"
    system "swift", "build",
      "--configuration", "release",
      "--disable-sandbox",
      "--scratch-path", injector_scratch,
      "--product", "LoupeInjector",
      "--sdk", simulator_sdk,
      "--triple", simulator_triple

    simulator_build_dir = simulator_triple.sub(/ios[0-9.]+-simulator/, "ios-simulator")
    injector_binary = injector_scratch/simulator_build_dir/"release/libLoupeInjector.dylib"
    (libexec/"LoupeInjector.framework").install injector_binary => "LoupeInjector"
  end

  test do
    assert_match "loupe: ok", shell_output("#{bin}/loupe doctor")
    assert_path_exists libexec/"LoupeInjector.framework/LoupeInjector"
    assert_equal(
      "#{libexec}/LoupeInjector.framework/LoupeInjector",
      shell_output("#{bin}/loupe injector-path").strip,
    )
  end
end
