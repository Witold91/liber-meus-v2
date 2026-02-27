import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]

  handleSubmit(event) {
    event.preventDefault()

    const action = this.inputTarget.value.trim()
    if (!action) return

    // Append user action as italic message immediately
    const log = document.getElementById("turn-log")
    if (log) {
      const userMsg = document.createElement("div")
      userMsg.style.cssText = "font-style:italic;color:#666;border-left:2px solid #444;padding-left:0.75rem;"
      userMsg.textContent = `> ${action}`
      log.appendChild(userMsg)
      log.scrollTop = log.scrollHeight
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
        if (log) log.scrollTop = log.scrollHeight
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
}
