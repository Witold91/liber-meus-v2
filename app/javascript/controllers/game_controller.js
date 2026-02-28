import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "worldPanel", "worldBtn"]

  connect() {
    this.turnLog = document.getElementById("turn-log")
    this.scrollFrame = null

    if (!this.turnLog) return

    this.turnLogObserver = new MutationObserver(() => {
      this.scheduleScrollToBottom()
    })

    this.turnLogObserver.observe(this.turnLog, {
      childList: true,
      subtree: true,
      characterData: true
    })

    this.scheduleScrollToBottom()
  }

  disconnect() {
    if (this.turnLogObserver) this.turnLogObserver.disconnect()
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)
  }

  handleSubmit(event) {
    event.preventDefault()

    const action = this.inputTarget.value.trim()
    if (!action) return

    // Append user action as italic message immediately
    const log = this.turnLog || document.getElementById("turn-log")
    if (log) {
      const userMsg = document.createElement("div")
      userMsg.style.cssText = "font-style:italic;color:#666;border-left:2px solid #444;padding-left:0.75rem;"
      userMsg.textContent = `> ${action}`
      log.appendChild(userMsg)
      this.scheduleScrollToBottom()
    }

    // Capture form data before disabling (disabled fields are excluded from FormData)
    const form = event.target
    const formData = new FormData(form)

    // Disable form while waiting
    this.inputTarget.disabled = true
    this.submitTarget.disabled = true
    this.submitTarget.textContent = "…"

    fetch(form.action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "text/vnd.turbo-stream.html, text/html"
      },
      body: formData
    })
      .then(response => response.text())
      .then(html => {
        Turbo.renderStreamMessage(html)
        this.scheduleScrollToBottom()
      })
      .catch(err => {
        console.error("Game submit error:", err)
      })
      .finally(() => {
        this.inputTarget.value = ""
        this.inputTarget.disabled = false
        this.submitTarget.disabled = false
        this.submitTarget.textContent = "→"
        this.inputTarget.focus()
      })
  }

  toggleWorldInfo() {
    const open = this.worldPanelTarget.classList.toggle("mobile-open")
    if (this.hasWorldBtnTarget) {
      this.worldBtnTarget.textContent = open ? "✕" : "World"
    }
  }

  scheduleScrollToBottom() {
    if (!this.turnLog) return
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)

    this.scrollFrame = requestAnimationFrame(() => {
      this.turnLog.scrollTop = this.turnLog.scrollHeight
      this.scrollFrame = null
    })
  }
}
