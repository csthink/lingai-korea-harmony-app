/** Visual values shared by the current client. No application behavior belongs here. */

export class UI {
  static readonly PAGE_INSET: number = 22;
  static readonly CONTENT_TOP: number = 48;
  static readonly SECTION_GAP: number = 24;
  static readonly CARD_RADIUS: number = 22;
  static readonly CONTROL_RADIUS: number = 12;
  static readonly TOUCH_MIN: number = 44;
  static readonly TITLE_SIZE: number = 23;
  static readonly BODY_SIZE: number = 16;
  static readonly CAPTION_SIZE: number = 13;
  static readonly NAV_HEIGHT: number = 78;

  static readonly ROW_RADIUS: number = 16;
  static get HEADER_BG(): string { return '#FFFFFF'; }
  static get BLUE_BORDER(): string { return '#B9D1F2'; }
  static get SELECTED_BORDER(): string { return '#A9D8C6'; }

  static get ON_PRIMARY(): string { return '#FFFFFF'; }
  static get BLUE(): string { return '#2C6FD6'; }
  static get ON_BLUE(): string { return '#FFFFFF'; }
  static get GREEN_SOFT(): string { return '#DFF4E9'; }
  static get BLUE_SOFT(): string { return '#E5F0FE'; }
  static get SURFACE_MUTED(): string { return '#EAF3F0'; }
  static get WARM(): string { return '#AD7214'; }
  static get WARM_SOFT(): string { return '#FFF2CC'; }
  static get DANGER_TEXT(): string { return '#B83545'; }
  static get DANGER_SOFT(): string { return '#FCE8EA'; }
  static get SHADOW(): string { return 'rgba(23,62,57,0.07)'; }
}
