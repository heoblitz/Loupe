class Loupe < Formula
  desc "CLI giving LLM agents runtime UI context from running iOS Simulator apps"
  homepage "https://github.com/heoblitz/Loupe"
  url "https://github.com/heoblitz/Loupe/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "892473e6c09b3e97eb65a00831a63a9b3f77da508818d2f78c8e10a3a213a1a6"
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

    simulator_arch = Hardware::CPU.arm? ? "arm64" : "x86_64"
    injector_scratch = buildpath/".build/homebrew-loupe-injector"
    injector_products = injector_scratch/"products"
    # Homebrew already sandboxes the install, so Xcode's nested manifest sandbox cannot start.
    ENV["IDEPackageSupportDisableManifestSandbox"] = "YES"
    xcodebuild \
      "-scheme", "LoupeInjector",
      "-destination", "generic/platform=iOS Simulator",
      "-configuration", "Release",
      "-derivedDataPath", injector_scratch/"DerivedData",
      "ARCHS=#{simulator_arch}",
      "ONLY_ACTIVE_ARCH=NO",
      "CONFIGURATION_BUILD_DIR=#{injector_products}",
      "build"

    injector_framework = injector_products/"PackageFrameworks/LoupeInjector.framework"
    libexec.install injector_framework
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
