const preview = document.querySelector('.preview');
const appearanceButtons = [...document.querySelectorAll('[data-appearance]')];

function showAppearance(appearance) {
  preview.dataset.preview = appearance;
  for (const button of appearanceButtons) {
    button.setAttribute('aria-pressed', String(button.dataset.appearance === appearance));
  }
  document.querySelector('#preview-light').hidden = appearance !== 'light';
  document.querySelector('#preview-dark').hidden = appearance !== 'dark';
}

for (const button of appearanceButtons) {
  button.addEventListener('click', () => showAppearance(button.dataset.appearance));
}
