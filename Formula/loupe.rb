class Loupe < Formula
  desc "CLI giving LLM agents runtime UI context from running Apple-platform apps"
  homepage "https://github.com/heoblitz/Loupe"
  url "https://github.com/heoblitz/Loupe/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "0c89d30066161b7ed7e58f4d0c3ece87a0f2ae13fb9889607a7b07002964795e"
  license "MIT"
  head "https://github.com/heoblitz/Loupe.git", branch: "main"

  bottle do
    root_url "https://github.com/heoblitz/Loupe/releases/download/v0.4.0"
    sha256 arm64_sequoia: "20dc71dde908e9a8ca0afd6ca83a2549a137fab2f7a6aa0cbb16d7028a835290"
    sha256 sequoia:       "f72f49b227768f8cf99749a9c0f196ca16a00ed4296d11e35c9ebbd2171d34fe"
  end

  depends_on xcode: ["16.0", :build]

  def swift_build(*args)
    build_args = ["build", "--configuration", "release", "--disable-sandbox", *args]
    swift = Utils.safe_popen_read("xcrun", "--find", "swift").strip
    compiler_environment = ENV.remove_cc_etc
    begin
      system swift, *build_args
      Pathname(Utils.safe_popen_read(swift, *build_args, "--show-bin-path").strip)
    ensure
      ENV.update(compiler_environment)
    end
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
    (libexec/"LoupeInjector.framework/macos").install(
      macos_injector_bin_path/"libLoupeInjector.dylib" => "LoupeInjector",
    )
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
