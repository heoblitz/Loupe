class Loupe < Formula
  desc "CLI giving LLM agents runtime UI context from running Apple-platform apps"
  homepage "https://github.com/heoblitz/Loupe"
  url "https://github.com/heoblitz/Loupe/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "90a1fcb637dcd3492f2ed60e026e7b15596a51d9ab03e8f262ba13250945225c"
  license "MIT"
  head "https://github.com/heoblitz/Loupe.git", branch: "main"

  depends_on xcode: ["16.0", :build]

  def swift_build(*args)
    build_args = ["build", "--configuration", "release", "--disable-sandbox", *args]
    system "swift", *build_args
    Pathname(Utils.safe_popen_read("swift", *build_args, "--show-bin-path").strip)
  end

  def install
    cli_bin_path = swift_build("--product", "loupe")
    bin.install cli_bin_path/"loupe"
    (pkgshare/"skills").install "skills/loupe" => "loupe"

    simulator_triple = Hardware::CPU.arm? ? "arm64-apple-ios15.0-simulator" : "x86_64-apple-ios15.0-simulator"
    simulator_sdk = Utils.safe_popen_read("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path").strip
    injector_bin_path = swift_build(
      "--scratch-path", buildpath/".build/homebrew-loupe-injector",
      "--product", "LoupeInjector",
      "--sdk", simulator_sdk,
      "--triple", simulator_triple
    )
    (libexec/"LoupeInjector.framework").install injector_bin_path/"libLoupeInjector.dylib" => "LoupeInjector"

    macos_injector_bin_path = swift_build(
      "--scratch-path", buildpath/".build/homebrew-loupe-macos-injector",
      "--product", "LoupeInjector"
    )
    (libexec/"LoupeInjector.framework/macos").install macos_injector_bin_path/"libLoupeInjector.dylib" => "LoupeInjector"
  end

  test do
    assert_match "loupe: ok", shell_output("#{bin}/loupe doctor")
    assert_path_exists libexec/"LoupeInjector.framework/LoupeInjector"
    assert_path_exists libexec/"LoupeInjector.framework/macos/LoupeInjector"
    assert_equal(
      "#{libexec}/LoupeInjector.framework/LoupeInjector",
      shell_output("#{bin}/loupe injector-path").strip,
    )
    assert_equal(
      "#{libexec}/LoupeInjector.framework/macos/LoupeInjector",
      shell_output("#{bin}/loupe injector-path --macos").strip,
    )
  end
end
