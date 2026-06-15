cask "progress-clock" do
  version "1.2.0"
  sha256 "4af4a7dc3f6dfa2e9ff665ed1e868e9e7a4c2c7d682e05b7f6a9fe0192b5e7d5"

  url "https://github.com/skakunm/progress_clock/releases/download/v#{version}/ProgressClock-#{version}.zip"
  name "Progress Clock"
  desc "Menu bar app that shows your day as a live progress bar"
  homepage "https://github.com/skakunm/progress_clock"

  app "ProgressClock.app"
end
