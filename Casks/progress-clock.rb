cask "progress-clock" do
  version "1.2.1"
  sha256 "33996522b1d91346bade5405f88169d76df982e31d454de76dfc8d1a041f1165"

  url "https://github.com/skakunm/progress_clock/releases/download/v#{version}/ProgressClock-#{version}.zip"
  name "Progress Clock"
  desc "Menu bar app that shows your day as a live progress bar"
  homepage "https://github.com/skakunm/progress_clock"

  app "ProgressClock.app"
end
