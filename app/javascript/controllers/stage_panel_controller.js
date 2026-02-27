import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "toggleBtn"]
  static values = {
    hideLabel: String,
    showLabel: String
  }

  toggle() {
    const hidden = this.bodyTarget.style.display === "none"
    this.bodyTarget.style.display = hidden ? "" : "none"
    this.toggleBtnTarget.textContent = hidden ? this.hideLabelValue : this.showLabelValue
  }
}
