// The page names no version, so it cannot go stale: every download button
// goes to the latest release's page. This asks GitHub which release that is
// and points the buttons at its disk image instead, naming the version beside
// them. If GitHub does not answer, nothing changes and the buttons still work.
const latest = "https://api.github.com/repos/cuonggt/shellhand/releases/latest";

async function latestRelease() {
  try {
    const kept = sessionStorage.getItem("shellhand-release");
    if (kept) return JSON.parse(kept);
  } catch {}
  const response = await fetch(latest, { headers: { Accept: "application/vnd.github+json" } });
  if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
  const release = await response.json();
  const image = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));
  const found = {
    version: String(release.tag_name || "").replace(/^v/, ""),
    url: image ? image.browser_download_url : "",
  };
  try {
    sessionStorage.setItem("shellhand-release", JSON.stringify(found));
  } catch {}
  return found;
}

latestRelease()
  .then(({ version, url }) => {
    if (!url) return;
    for (const link of document.querySelectorAll("[data-download]")) link.href = url;
    for (const label of document.querySelectorAll("[data-version]")) {
      label.textContent = `Version ${version} · `;
    }
  })
  .catch(() => {});

// A copy button is shown only where it can work, and says what it did both
// on itself and to a screen reader.
const status = document.getElementById("copy-status");
for (const button of document.querySelectorAll("[data-copy]")) {
  if (!navigator.clipboard) continue;
  const source = document.getElementById(button.dataset.copy);
  button.hidden = false;
  button.setAttribute("aria-label", "Copy the Homebrew commands");
  let reset;
  button.addEventListener("click", async () => {
    clearTimeout(reset);
    try {
      await navigator.clipboard.writeText(source.textContent.trim() + "\n");
      button.textContent = "Copied";
      status.textContent = "The Homebrew commands are on the clipboard.";
    } catch {
      button.textContent = "Failed";
      status.textContent = "Could not copy; select the commands instead.";
    }
    reset = setTimeout(() => {
      button.textContent = "Copy";
      status.textContent = "";
    }, 2000);
  });
}
