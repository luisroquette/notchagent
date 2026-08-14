#include <Arduino.h>
#include <ArduinoJson.h>
#include <Arduino_GFX_Library.h>
#include <inttypes.h>
#include <lvgl.h>
#include "config.h"
#include "desk_protocol.h"
#include "touch.h"

namespace {

constexpr uint32_t kPanel = 0x000000;
constexpr uint32_t kSurface = 0x16161B;
constexpr uint32_t kRaised = 0x202026;
constexpr uint32_t kCoral = 0xF47A3C;
constexpr uint32_t kText = 0xF2F2F2;
constexpr uint32_t kMuted = 0x9E9EA6;
constexpr uint32_t kOK = 0x7AC57F;
constexpr uint32_t kWarning = 0xEFAA4E;
constexpr uint32_t kDanger = 0xE5484D;
constexpr uint64_t kResetBoundaryToleranceMs = 120000;
constexpr int kPageCount = 4;

struct ProviderState {
  char id[16] = "";
  char refresh[12] = "idle";
  char window[10] = "";
  float remaining = -1;
  float burn = -1;
  int64_t tokens = 0;
  uint8_t attention = 0;
  uint64_t resetEpochMs = 0;
  uint64_t exhaustEpochMs = 0;
};

struct ModelState {
  char name[33] = "";
  int64_t tokens = 0;
  char status[10] = "";
  int latency = -1;
};

struct AlertTracker {
  char id[16] = "";
  char window[10] = "";
  float lowestRemaining = 101;
  uint64_t resetEpochMs = 0;
  uint8_t firedMask = 0;
  bool initialized = false;
  bool observed = false;
};

ProviderState providers[8];
ModelState models[8];
AlertTracker alertTrackers[8];
uint8_t alertThresholds[5] = {100, 75, 50, 25, 5};
size_t alertThresholdCount = 5;
bool runnerEnabled = true;
int64_t rhythm[24] = {};
float burnAgeSeconds[48] = {};
float burnUsedPercent[48] = {};
size_t burnPointCount = 0;
size_t providerCount = 0;
size_t modelCount = 0;
uint8_t overallAttention = 0;
bool paused = false;
uint32_t lastSnapshotMs = 0;
bool dataCleared = true;
bool hostRecognized = false;
uint32_t invalidFrameCount = 0;
uint32_t handshakeCount = 0;
uint32_t lastRenderedAt = 0;
uint32_t activeRenderIntervalCount = 0;
uint32_t activeRenderIntervalTotalMs = 0;
uint32_t fpsWindowStartedAt = 0;
float measuredFPS = 0;
uint64_t snapshotEpochMs = 0;

Arduino_Canvas *canvas = nullptr;
uint16_t *canvasPixels = nullptr;
DeskTouch touch;
lv_obj_t *pages[kPageCount] = {};
lv_obj_t *navButtons[kPageCount] = {};
lv_obj_t *navLabels[kPageCount] = {};
lv_obj_t *navIndicators[kPageCount] = {};
lv_obj_t *connectionLabel = nullptr;
char ambientStatus[128] = "";
lv_obj_t *providerNames[2] = {};
lv_obj_t *providerValues[2] = {};
lv_obj_t *providerCaptions[2] = {};
lv_obj_t *providerDetails[2] = {};
lv_obj_t *providerStatuses[2] = {};
lv_obj_t *providerGauge[2][10] = {};
lv_obj_t *burnHero = nullptr;
lv_obj_t *burnHeroCaption = nullptr;
lv_obj_t *burnProvider = nullptr;
lv_obj_t *burnVerdictPanel = nullptr;
lv_obj_t *burnVerdict = nullptr;
lv_obj_t *burnDetail = nullptr;
lv_obj_t *burnStatus = nullptr;
lv_obj_t *burnGauge[20] = {};
lv_obj_t *burnMetricValues[3] = {};
lv_obj_t *rhythmBars[24] = {};
lv_obj_t *rhythmMetricValues[3] = {};
lv_obj_t *modelSummary = nullptr;
lv_obj_t *modelRows[4] = {};
lv_obj_t *modelLabels[4] = {};
lv_obj_t *modelTokenLabels[4] = {};
lv_obj_t *modelStatusLabels[4] = {};
lv_obj_t *modelGauge[4][10] = {};
lv_obj_t *gameMascot = nullptr;
lv_obj_t *gamePixels[5][8] = {};
lv_obj_t *gameObstacles[4] = {};
lv_obj_t *gameGround[40] = {};
lv_obj_t *gameTitle = nullptr;
lv_obj_t *gameStatus = nullptr;
float gameObstacleX[4] = {190, 310, 445, 590};
uint32_t gameScore = 0;
uint32_t gameLastTick = 0;
float gameDistance = 0;
float jumpElapsedMs = 0;
bool jumpActive = false;
bool gameOver = false;
bool runnerCrashed = false;
uint32_t runnerCrashedAt = 0;
lv_obj_t *alertOverlay = nullptr;
lv_obj_t *alertMascotPixels[6][8] = {};
lv_obj_t *alertProviderLabel = nullptr;
lv_obj_t *alertPercentLabel = nullptr;
lv_obj_t *alertHeadlineLabel = nullptr;
lv_obj_t *alertMessageLabel = nullptr;
lv_obj_t *alertSegments[16] = {};
lv_obj_t *alertDismissLabel = nullptr;
uint8_t activeAlertThreshold = 0;
uint32_t alertShownAt = 0;
int activePage = 0;
int transitionFromPage = -1;
int transitionToPage = -1;
int transitionDirection = 0;
uint32_t transitionStartedAt = 0;
int8_t pendingSwipe = 0;
bool touchGestureActive = false;
bool touchGestureRecognized = false;
uint16_t touchStartX = 0;
uint16_t touchStartY = 0;
uint16_t touchLastX = 0;
uint16_t touchLastY = 0;
uint32_t touchLastSampleAt = 0;
uint32_t lastUserInteractionAt = 0;

uint8_t *packetBuffer = nullptr;
uint8_t *decodedBuffer = nullptr;
uint8_t *encodedBuffer = nullptr;
size_t packetLength = 0;
uint32_t outgoingSequence = 0;

lv_obj_t *label(lv_obj_t *parent, const char *text, const lv_font_t *font,
                uint32_t color, int x, int y) {
  lv_obj_t *object = lv_label_create(parent);
  lv_label_set_text(object, text);
  lv_obj_set_style_text_font(object, font, 0);
  lv_obj_set_style_text_color(object, lv_color_hex(color), 0);
  lv_obj_set_pos(object, x, y);
  return object;
}

void styleTracking(lv_obj_t *object, int pixels = 1) {
  lv_obj_set_style_text_letter_space(object, pixels, 0);
}

lv_obj_t *surface(lv_obj_t *parent, int x, int y, int width, int height, int radius = 12) {
  lv_obj_t *object = lv_obj_create(parent);
  lv_obj_set_pos(object, x, y);
  lv_obj_set_size(object, width, height);
  lv_obj_set_style_bg_color(object, lv_color_hex(kSurface), 0);
  lv_obj_set_style_bg_opa(object, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(object, lv_color_hex(kRaised), 0);
  lv_obj_set_style_border_width(object, 1, 0);
  lv_obj_set_style_radius(object, radius, 0);
  lv_obj_set_style_pad_all(object, 0, 0);
  lv_obj_remove_flag(object, LV_OBJ_FLAG_SCROLLABLE);
  return object;
}

void displayFlush(lv_display_t *display, const lv_area_t *, uint8_t *pixels) {
  const uint16_t *source = reinterpret_cast<uint16_t *>(pixels);
  for (int y = 0; y < DESK_SCREEN_HEIGHT; ++y) {
    for (int x = 0; x < DESK_SCREEN_WIDTH; ++x) {
      canvasPixels[(DESK_SCREEN_WIDTH - 1 - x) * DESK_SCREEN_HEIGHT + y] =
          source[y * DESK_SCREEN_WIDTH + x];
    }
  }
  canvas->flush();
  const uint32_t renderedAt = millis();
  const uint32_t interval = lastRenderedAt ? renderedAt - lastRenderedAt : 0;
  // Only consecutive animation frames measure render cadence. Isolated dirty
  // updates on a static page must not be reported as a 1-2 FPS panel fault.
  if (interval > 0 && interval <= 250) {
    ++activeRenderIntervalCount;
    activeRenderIntervalTotalMs += interval;
  }
  lastRenderedAt = renderedAt;
  lv_display_flush_ready(display);
}

void touchRead(lv_indev_t *, lv_indev_data_t *data) {
  uint16_t x = 0, y = 0;
  if (touch.read(x, y)) {
    lastUserInteractionAt = millis();
    ambientStatus[0] = '\0';
    lv_label_set_text(connectionLabel, "MANUAL");
    if (!touchGestureActive) {
      touchGestureActive = true;
      touchGestureRecognized = false;
      touchStartX = x;
      touchStartY = y;
    } else if (!touchGestureRecognized) {
      const int deltaX = static_cast<int>(x) - touchStartX;
      const int deltaY = static_cast<int>(y) - touchStartY;
      if (abs(deltaX) >= 56 && abs(deltaX) > abs(deltaY) * 3 / 2) {
        pendingSwipe = deltaX < 0 ? 1 : -1;
        touchGestureRecognized = true;
      }
    }
    touchLastX = x;
    touchLastY = y;
    touchLastSampleAt = millis();
    data->point.x = x;
    data->point.y = y;
    data->state = LV_INDEV_STATE_PRESSED;
  } else if (touchGestureActive && millis() - touchLastSampleAt < 120) {
    data->point.x = touchLastX;
    data->point.y = touchLastY;
    data->state = LV_INDEV_STATE_PRESSED;
  } else {
    data->state = LV_INDEV_STATE_RELEASED;
    touchGestureActive = false;
  }
}

void updateNavState(int page) {
  for (int i = 0; i < kPageCount; ++i) {
    lv_obj_set_style_text_color(navLabels[i], lv_color_hex(i == page ? kCoral : kMuted), 0);
    if (i == page) lv_obj_remove_flag(navIndicators[i], LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(navIndicators[i], LV_OBJ_FLAG_HIDDEN);
  }
}

void showPage(int page) {
  if (page < 0 || page >= kPageCount) return;
  activePage = page;
  for (int i = 0; i < kPageCount; ++i) {
    if (i == page) lv_obj_remove_flag(pages[i], LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(pages[i], LV_OBJ_FLAG_HIDDEN);
  }
  updateNavState(page);
}

void navigatePage(int page) {
  if (page < 0 || page >= kPageCount || page == activePage || transitionFromPage >= 0) return;
  transitionFromPage = activePage;
  transitionToPage = page;
  transitionDirection = page > activePage ? 1 : -1;
  transitionStartedAt = millis();
  activePage = page;
  for (int i = 0; i < kPageCount; ++i) {
    if (i == transitionFromPage || i == transitionToPage)
      lv_obj_remove_flag(pages[i], LV_OBJ_FLAG_HIDDEN);
    else
      lv_obj_add_flag(pages[i], LV_OBJ_FLAG_HIDDEN);
  }
  lv_obj_set_x(pages[transitionFromPage], 8);
  lv_obj_set_x(pages[transitionToPage], 8 + transitionDirection * 464);
  updateNavState(page);
}

void updatePageTransition() {
  if (transitionFromPage < 0) return;
  const float progress = min(1.0f, (millis() - transitionStartedAt) / 180.0f);
  const float eased = 1.0f - powf(1.0f - progress, 3.0f);
  lv_obj_set_x(pages[transitionFromPage], 8 - transitionDirection * static_cast<int>(464 * eased));
  lv_obj_set_x(pages[transitionToPage], 8 + transitionDirection * static_cast<int>(464 * (1.0f - eased)));
  if (progress >= 1.0f) {
    lv_obj_add_flag(pages[transitionFromPage], LV_OBJ_FLAG_HIDDEN);
    lv_obj_set_x(pages[transitionFromPage], 8);
    lv_obj_set_x(pages[transitionToPage], 8);
    transitionFromPage = transitionToPage = -1;
  }
}

void navEvent(lv_event_t *event) {
  navigatePage(static_cast<int>(reinterpret_cast<intptr_t>(lv_event_get_user_data(event))));
}

constexpr uint8_t kGaitA[5][8] = {
  {0,1,1,0,0,1,1,0}, {1,1,1,1,1,1,1,1}, {1,2,1,1,1,2,1,1},
  {1,1,1,1,1,1,1,1}, {0,1,0,0,1,0,0,0},
};
constexpr uint8_t kGaitB[5][8] = {
  {0,1,1,0,0,1,1,0}, {1,1,1,1,1,1,1,1}, {1,2,1,1,1,2,1,1},
  {1,1,1,1,1,1,1,1}, {0,0,1,0,0,0,1,0},
};
constexpr uint8_t kDead[5][8] = {
  {0,0,0,0,0,0,0,0}, {0,1,0,0,1,0,0,0}, {1,1,1,1,1,1,1,1},
  {1,2,1,1,1,2,1,1}, {1,1,1,1,1,1,1,1},
};
constexpr uint8_t kClawd[6][8] = {
  {0,1,1,0,0,1,1,0}, {1,1,1,1,1,1,1,1}, {1,2,2,1,1,2,2,1},
  {1,1,1,1,1,1,1,1}, {1,1,1,1,1,1,1,1}, {0,1,0,1,1,0,1,0},
};

void jump() {
  if (runnerCrashed) {
    gameObstacleX[0] = 190;
    gameObstacleX[1] = 320;
    gameObstacleX[2] = 450;
    gameObstacleX[3] = 590;
    runnerCrashed = false;
    jumpActive = false;
    jumpElapsedMs = 0;
    gameScore = 0;
    return;
  }
  if (!runnerEnabled || gameOver || jumpActive) return;
  jumpActive = true;
  jumpElapsedMs = 0;
}

void gameTouchEvent(lv_event_t *) {
  jump();
  if (jumpActive) {
    lv_obj_set_y(gameMascot, 26);
    lv_label_set_text(gameStatus, "JUMP!");
  }
}

void dismissDeskAlert() {
  if (!alertOverlay || lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) return;
  lv_obj_add_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN);
  activeAlertThreshold = 0;
}

void alertTouchEvent(lv_event_t *) {
  dismissDeskAlert();
}

void setGameSprite(const uint8_t grid[5][8], uint32_t tint) {
  for (int row = 0; row < 5; ++row) {
    for (int col = 0; col < 8; ++col) {
      const uint8_t cell = grid[row][col];
      if (!cell) lv_obj_add_flag(gamePixels[row][col], LV_OBJ_FLAG_HIDDEN);
      else {
        lv_obj_remove_flag(gamePixels[row][col], LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_bg_color(gamePixels[row][col],
          lv_color_hex(cell == 2 ? kPanel : tint), 0);
      }
    }
  }
}

void createGame(lv_obj_t *parent) {
  lv_obj_t *track = surface(parent, 0, 154, 464, 70, 10);
  lv_obj_add_flag(track, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(track, gameTouchEvent, LV_EVENT_PRESSED, nullptr);
  gameTitle = label(track, "CLAWD RUNNER", &lv_font_montserrat_12, kCoral, 8, 4);
  styleTracking(gameTitle, 2);
  gameStatus = label(track, "TAP TRACK TO JUMP", &lv_font_montserrat_12, kMuted, 216, 4);
  lv_obj_set_width(gameStatus, 238);
  lv_obj_set_style_text_align(gameStatus, LV_TEXT_ALIGN_RIGHT, 0);
  styleTracking(gameStatus, 1);

  for (int i = 0; i < 40; ++i) {
    gameGround[i] = lv_obj_create(track);
    lv_obj_remove_flag(gameGround[i], LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(gameGround[i], i * 12, 62);
    lv_obj_set_size(gameGround[i], 6, 2);
    lv_obj_set_style_bg_color(gameGround[i], lv_color_hex(kCoral), 0);
    lv_obj_set_style_bg_opa(gameGround[i], LV_OPA_40, 0);
    lv_obj_set_style_border_width(gameGround[i], 0, 0);
  }

  gameMascot = lv_obj_create(track);
  lv_obj_remove_flag(gameMascot, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_pos(gameMascot, 24, 32);
  lv_obj_set_size(gameMascot, 48, 30);
  lv_obj_set_style_bg_opa(gameMascot, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(gameMascot, 0, 0);
  lv_obj_set_style_pad_all(gameMascot, 0, 0);
  lv_obj_remove_flag(gameMascot, LV_OBJ_FLAG_SCROLLABLE);
  for (int row = 0; row < 5; ++row) {
    for (int col = 0; col < 8; ++col) {
      gamePixels[row][col] = lv_obj_create(gameMascot);
      lv_obj_remove_flag(gamePixels[row][col], LV_OBJ_FLAG_CLICKABLE);
      lv_obj_set_pos(gamePixels[row][col], col * 6, row * 6);
      lv_obj_set_size(gamePixels[row][col], 5, 5);
      lv_obj_set_style_border_width(gamePixels[row][col], 0, 0);
      lv_obj_set_style_radius(gamePixels[row][col], 0, 0);
    }
  }

  for (int obstacle = 0; obstacle < 4; ++obstacle) {
    gameObstacles[obstacle] = lv_obj_create(track);
    lv_obj_remove_flag(gameObstacles[obstacle], LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(gameObstacles[obstacle], obstacle % 2 ? 8 : 10, obstacle % 2 ? 14 : 18);
    lv_obj_set_y(gameObstacles[obstacle], obstacle % 2 ? 48 : 44);
    lv_obj_set_style_bg_color(gameObstacles[obstacle], lv_color_hex(kOK), 0);
    lv_obj_set_style_border_width(gameObstacles[obstacle], 0, 0);
    lv_obj_set_style_radius(gameObstacles[obstacle], 1, 0);
    lv_obj_remove_flag(gameObstacles[obstacle], LV_OBJ_FLAG_SCROLLABLE);
    if (obstacle % 2 == 0) {
      lv_obj_t *arm = lv_obj_create(gameObstacles[obstacle]);
      lv_obj_remove_flag(arm, LV_OBJ_FLAG_CLICKABLE);
      lv_obj_set_pos(arm, 0, 6);
      lv_obj_set_size(arm, 10, 4);
      lv_obj_set_style_bg_color(arm, lv_color_hex(kOK), 0);
      lv_obj_set_style_border_width(arm, 0, 0);
      lv_obj_set_style_radius(arm, 0, 0);
    }
  }
  setGameSprite(kGaitA, kCoral);
}

void createAlertOverlay(lv_obj_t *screen) {
  alertOverlay = lv_obj_create(screen);
  lv_obj_set_pos(alertOverlay, 4, 4);
  lv_obj_set_size(alertOverlay, 472, 312);
  lv_obj_set_style_bg_color(alertOverlay, lv_color_hex(0x110506), 0);
  lv_obj_set_style_bg_opa(alertOverlay, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(alertOverlay, lv_color_hex(kDanger), 0);
  lv_obj_set_style_border_width(alertOverlay, 3, 0);
  lv_obj_set_style_radius(alertOverlay, 18, 0);
  lv_obj_set_style_pad_all(alertOverlay, 0, 0);
  lv_obj_remove_flag(alertOverlay, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(alertOverlay, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(alertOverlay, alertTouchEvent, LV_EVENT_CLICKED, nullptr);

  for (int row = 0; row < 6; ++row) {
    for (int col = 0; col < 8; ++col) {
      alertMascotPixels[row][col] = lv_obj_create(alertOverlay);
      lv_obj_remove_flag(alertMascotPixels[row][col], LV_OBJ_FLAG_CLICKABLE);
      lv_obj_set_pos(alertMascotPixels[row][col], 28 + col * 10, 104 + row * 10);
      lv_obj_set_size(alertMascotPixels[row][col], 9, 9);
      lv_obj_set_style_border_width(alertMascotPixels[row][col], 0, 0);
      lv_obj_set_style_radius(alertMascotPixels[row][col], 0, 0);
      if (!kClawd[row][col]) lv_obj_add_flag(alertMascotPixels[row][col], LV_OBJ_FLAG_HIDDEN);
    }
  }
  alertProviderLabel = label(alertOverlay, "PROVIDER / 5H WINDOW", &lv_font_montserrat_14, kMuted, 130, 72);
  styleTracking(alertProviderLabel, 2);
  alertPercentLabel = label(alertOverlay, "--%", &lv_font_montserrat_48, kDanger, 130, 98);
  alertHeadlineLabel = label(alertOverlay, "HEADS UP", &lv_font_montserrat_16, kDanger, 132, 158);
  styleTracking(alertHeadlineLabel, 2);
  alertMessageLabel = label(alertOverlay, "Quota milestone reached.", &lv_font_montserrat_14, kMuted, 132, 185);
  for (int i = 0; i < 16; ++i) {
    alertSegments[i] = lv_obj_create(alertOverlay);
    lv_obj_remove_flag(alertSegments[i], LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(alertSegments[i], 132 + i * 18, 218);
    lv_obj_set_size(alertSegments[i], 15, 8);
    lv_obj_set_style_bg_color(alertSegments[i], lv_color_hex(kRaised), 0);
    lv_obj_set_style_border_width(alertSegments[i], 0, 0);
    lv_obj_set_style_radius(alertSegments[i], 2, 0);
  }
  alertDismissLabel = label(alertOverlay, "TAP TO DISMISS", &lv_font_montserrat_12, kMuted, 340, 280);
  styleTracking(alertDismissLabel, 1);
  lv_obj_add_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN);
}

void createUI() {
  lv_obj_t *screen = lv_screen_active();
  lv_obj_set_style_bg_color(screen, lv_color_hex(kPanel), 0);
  lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
  for (int row = 0; row < 5; ++row) {
    for (int col = 0; col < 8; ++col) {
      if (!kGaitA[row][col]) continue;
      lv_obj_t *pixel = lv_obj_create(screen);
      lv_obj_remove_flag(pixel, LV_OBJ_FLAG_CLICKABLE);
      lv_obj_set_pos(pixel, 5 + col * 4, 8 + row * 4);
      lv_obj_set_size(pixel, 3, 3);
      lv_obj_set_style_bg_color(pixel, lv_color_hex(kGaitA[row][col] == 2 ? kPanel : kCoral), 0);
      lv_obj_set_style_border_width(pixel, 0, 0);
      lv_obj_set_style_radius(pixel, 0, 0);
    }
  }
  lv_obj_t *brand = label(screen, "NOTCHAGENT / CF GAUSS", &lv_font_montserrat_14, kCoral, 42, 8);
  styleTracking(brand, 2);
  connectionLabel = label(screen, "WAITING", &lv_font_montserrat_12, kMuted, 366, 10);
  lv_obj_set_width(connectionLabel, 104);
  lv_label_set_long_mode(connectionLabel, LV_LABEL_LONG_SCROLL_CIRCULAR);
  lv_obj_set_style_text_align(connectionLabel, LV_TEXT_ALIGN_RIGHT, 0);
  styleTracking(connectionLabel, 1);
  lv_obj_t *divider = lv_obj_create(screen);
  lv_obj_remove_flag(divider, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_pos(divider, 8, 40);
  lv_obj_set_size(divider, 464, 2);
  lv_obj_set_style_bg_color(divider, lv_color_hex(kCoral), 0);
  lv_obj_set_style_border_width(divider, 0, 0);

  const char *titles[kPageCount] = {"NOW", "BURN", "RHYTHM", "MODELS"};
  for (int i = 0; i < kPageCount; ++i) {
    pages[i] = lv_obj_create(screen);
    lv_obj_set_pos(pages[i], 8, 44);
    lv_obj_set_size(pages[i], 464, 224);
    lv_obj_set_style_bg_color(pages[i], lv_color_hex(kPanel), 0);
    lv_obj_set_style_border_width(pages[i], 0, 0);
    lv_obj_set_style_pad_all(pages[i], 0, 0);
    lv_obj_remove_flag(pages[i], LV_OBJ_FLAG_SCROLLABLE);
  }
  for (int i = 0; i < kPageCount; ++i) {
    navButtons[i] = lv_button_create(screen);
    lv_obj_set_pos(navButtons[i], 5 + i * 117, 272);
    lv_obj_set_size(navButtons[i], 115, 44);
    lv_obj_set_style_bg_color(navButtons[i], lv_color_hex(kPanel), 0);
    lv_obj_set_style_bg_opa(navButtons[i], LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(navButtons[i], 0, 0);
    lv_obj_set_style_radius(navButtons[i], 0, 0);
    lv_obj_add_event_cb(navButtons[i], navEvent, LV_EVENT_CLICKED, reinterpret_cast<void *>(i));
    navLabels[i] = lv_label_create(navButtons[i]);
    lv_label_set_text(navLabels[i], titles[i]);
    lv_obj_set_style_text_font(navLabels[i], &lv_font_montserrat_12, 0);
    styleTracking(navLabels[i], 1);
    lv_obj_align(navLabels[i], LV_ALIGN_CENTER, 0, 2);
    navIndicators[i] = lv_obj_create(navButtons[i]);
    lv_obj_remove_flag(navIndicators[i], LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(navIndicators[i], 34, 3);
    lv_obj_align(navIndicators[i], LV_ALIGN_TOP_MID, 0, 1);
    lv_obj_set_style_bg_color(navIndicators[i], lv_color_hex(kCoral), 0);
    lv_obj_set_style_border_width(navIndicators[i], 0, 0);
    lv_obj_set_style_radius(navIndicators[i], 2, 0);
  }

  for (int i = 0; i < 2; ++i) {
    lv_obj_t *card = surface(pages[0], i * 232, 0, 226, 148, 12);
    providerNames[i] = label(card, "--", &lv_font_montserrat_12, kMuted, 12, 7);
    styleTracking(providerNames[i], 2);
    providerValues[i] = label(card, "--", &lv_font_montserrat_40, kText, 12, 25);
    providerCaptions[i] = label(card, "WAITING FOR DATA", &lv_font_montserrat_12, kMuted, 12, 70);
    styleTracking(providerCaptions[i], 1);
    for (int segment = 0; segment < 10; ++segment) {
      providerGauge[i][segment] = lv_obj_create(card);
      lv_obj_set_pos(providerGauge[i][segment], 12 + segment * 19, 91);
      lv_obj_set_size(providerGauge[i][segment], 15, 8);
      lv_obj_set_style_bg_color(providerGauge[i][segment], lv_color_hex(kRaised), 0);
      lv_obj_set_style_border_width(providerGauge[i][segment], 0, 0);
      lv_obj_set_style_radius(providerGauge[i][segment], 2, 0);
    }
    providerDetails[i] = label(card, "", &lv_font_montserrat_12, kMuted, 12, 108);
    providerStatuses[i] = label(card, "NO DATA", &lv_font_montserrat_12, kMuted, 12, 130);
    styleTracking(providerStatuses[i], 1);
  }

  lv_obj_t *burnCard = surface(pages[1], 0, 0, 464, 224, 14);
  lv_obj_t *burnTitle = label(burnCard, "BURN FORECAST", &lv_font_montserrat_12, kCoral, 14, 10);
  styleTracking(burnTitle, 1);
  lv_obj_t *burnQuestion = label(burnCard, "WILL I RUN OUT?", &lv_font_montserrat_12, kMuted, 146, 10);
  styleTracking(burnQuestion, 1);
  burnProvider = label(burnCard, "--", &lv_font_montserrat_12, kCoral, 366, 10);
  lv_obj_set_width(burnProvider, 82);
  lv_obj_set_style_text_align(burnProvider, LV_TEXT_ALIGN_RIGHT, 0);
  burnHero = label(burnCard, "--%", &lv_font_montserrat_40, kText, 14, 36);
  burnHeroCaption = label(burnCard, "LIMIT LEFT", &lv_font_montserrat_12, kMuted, 128, 57);
  styleTracking(burnHeroCaption, 2);
  burnVerdictPanel = surface(burnCard, 216, 34, 232, 62, 8);
  lv_obj_set_style_bg_color(burnVerdictPanel, lv_color_hex(kPanel), 0);
  burnVerdict = label(burnVerdictPanel, "LEARNING YOUR PACE", &lv_font_montserrat_16, kMuted, 12, 8);
  lv_obj_set_width(burnVerdict, 208);
  burnStatus = label(burnVerdictPanel, "USE NOTCHAGENT FOR A FEW MINUTES.", &lv_font_montserrat_12, kMuted, 12, 33);
  lv_obj_set_width(burnStatus, 208);
  lv_obj_set_height(burnStatus, 28);
  lv_label_set_long_mode(burnStatus, LV_LABEL_LONG_WRAP);
  styleTracking(burnStatus, 1);
  lv_obj_t *runwayLabel = label(burnCard, "AVAILABLE RUNWAY", &lv_font_montserrat_12, kMuted, 14, 101);
  styleTracking(runwayLabel, 1);
  for (int segment = 0; segment < 20; ++segment) {
    burnGauge[segment] = lv_obj_create(burnCard);
    lv_obj_set_pos(burnGauge[segment], 14 + segment * 22, 120);
    lv_obj_set_size(burnGauge[segment], 17, 10);
    lv_obj_set_style_bg_color(burnGauge[segment], lv_color_hex(kRaised), 0);
    lv_obj_set_style_border_width(burnGauge[segment], 0, 0);
    lv_obj_set_style_radius(burnGauge[segment], 2, 0);
  }
  const char *metricCaptions[3] = {"WINDOW", "RESET", "PACE"};
  const int metricX[3] = {14, 162, 310};
  for (int metric = 0; metric < 3; ++metric) {
    lv_obj_t *metricCard = surface(burnCard, metricX[metric], 142, metric == 2 ? 138 : 140, 48, 7);
    lv_obj_set_style_bg_color(metricCard, lv_color_hex(kPanel), 0);
    lv_obj_t *caption = label(metricCard, metricCaptions[metric], &lv_font_montserrat_12, kMuted, 10, 6);
    styleTracking(caption, 1);
    burnMetricValues[metric] = label(metricCard, "--", &lv_font_montserrat_16, kText, 10, 23);
    lv_obj_set_width(burnMetricValues[metric], metric == 2 ? 118 : 120);
  }
  burnDetail = label(burnCard, "I'LL FORECAST RISK AS DATA ARRIVES.", &lv_font_montserrat_12, kMuted, 14, 202);
  lv_obj_set_width(burnDetail, 434);
  lv_label_set_long_mode(burnDetail, LV_LABEL_LONG_CLIP);

  lv_obj_t *rhythmTitle = label(pages[2], "RHYTHM  /  WHEN DO I WORK MOST?", &lv_font_montserrat_12, kCoral, 4, 5);
  styleTracking(rhythmTitle, 1);
  lv_obj_t *rhythmScope = label(pages[2], "WEEKLY PATTERN", &lv_font_montserrat_12, kMuted, 330, 5);
  lv_obj_set_width(rhythmScope, 130);
  lv_obj_set_style_text_align(rhythmScope, LV_TEXT_ALIGN_RIGHT, 0);
  const char *rhythmCaptions[3] = {"PEAK HOUR", "WEEK TOTAL", "STRONGEST"};
  const int rhythmMetricX[3] = {0, 156, 312};
  for (int metric = 0; metric < 3; ++metric) {
    lv_obj_t *metricCard = surface(pages[2], rhythmMetricX[metric], 29, metric == 2 ? 152 : 148, 50, 8);
    lv_obj_set_style_bg_color(metricCard, lv_color_hex(kPanel), 0);
    lv_obj_t *caption = label(metricCard, rhythmCaptions[metric], &lv_font_montserrat_12, kMuted, 10, 7);
    styleTracking(caption, 1);
    rhythmMetricValues[metric] = label(metricCard, "--", &lv_font_montserrat_16, kText, 10, 25);
    lv_obj_set_width(rhythmMetricValues[metric], metric == 2 ? 132 : 128);
    lv_label_set_long_mode(rhythmMetricValues[metric], LV_LABEL_LONG_CLIP);
  }
  lv_obj_t *flowLabel = label(pages[2], "HOURLY TOKEN FLOW", &lv_font_montserrat_12, kMuted, 4, 88);
  styleTracking(flowLabel, 1);
  const int rhythmGridY[3] = {105, 150, 196};
  for (int grid = 0; grid < 3; ++grid) {
    lv_obj_t *line = lv_obj_create(pages[2]);
    lv_obj_set_pos(line, 4, rhythmGridY[grid]);
    lv_obj_set_size(line, 456, 1);
    lv_obj_set_style_bg_color(line, lv_color_hex(kRaised), 0);
    lv_obj_set_style_bg_opa(line, grid == 2 ? LV_OPA_COVER : LV_OPA_50, 0);
    lv_obj_set_style_border_width(line, 0, 0);
  }
  for (int i = 0; i < 24; ++i) {
    rhythmBars[i] = lv_obj_create(pages[2]);
    lv_obj_set_pos(rhythmBars[i], 5 + i * 19, 194);
    lv_obj_set_size(rhythmBars[i], 11, 2);
    lv_obj_set_style_bg_color(rhythmBars[i], lv_color_hex(kCoral), 0);
    lv_obj_set_style_border_width(rhythmBars[i], 0, 0);
    lv_obj_set_style_radius(rhythmBars[i], 2, 0);
  }
  label(pages[2], "00", &lv_font_montserrat_12, kMuted, 4, 204);
  label(pages[2], "06", &lv_font_montserrat_12, kMuted, 116, 204);
  label(pages[2], "12", &lv_font_montserrat_12, kMuted, 232, 204);
  label(pages[2], "18", &lv_font_montserrat_12, kMuted, 346, 204);
  label(pages[2], "23", &lv_font_montserrat_12, kMuted, 442, 204);

  lv_obj_t *modelsTitle = label(pages[3], "MODELS  /  WHO IS DOING THE WORK?", &lv_font_montserrat_12, kCoral, 4, 5);
  styleTracking(modelsTitle, 1);
  modelSummary = label(pages[3], "0 TRACKED", &lv_font_montserrat_12, kMuted, 284, 5);
  lv_obj_set_width(modelSummary, 176);
  lv_obj_set_style_text_align(modelSummary, LV_TEXT_ALIGN_RIGHT, 0);
  for (int i = 0; i < 4; ++i) {
    modelRows[i] = surface(pages[3], 0, 34 + i * 47, 464, 42, 8);
    lv_obj_t *rank = label(modelRows[i], i == 0 ? "01" : i == 1 ? "02" : i == 2 ? "03" : "04",
                           &lv_font_montserrat_12, kCoral, 10, 8);
    styleTracking(rank, 1);
    modelLabels[i] = label(modelRows[i], "NO MODEL", &lv_font_montserrat_14, kMuted, 42, 5);
    lv_obj_set_width(modelLabels[i], 218);
    lv_label_set_long_mode(modelLabels[i], LV_LABEL_LONG_CLIP);
    modelTokenLabels[i] = label(modelRows[i], "--", &lv_font_montserrat_14, kMuted, 268, 5);
    lv_obj_set_width(modelTokenLabels[i], 88);
    lv_obj_set_style_text_align(modelTokenLabels[i], LV_TEXT_ALIGN_RIGHT, 0);
    modelStatusLabels[i] = label(modelRows[i], "NO DATA", &lv_font_montserrat_12, kMuted, 366, 7);
    lv_obj_set_width(modelStatusLabels[i], 84);
    lv_obj_set_style_text_align(modelStatusLabels[i], LV_TEXT_ALIGN_RIGHT, 0);
    for (int segment = 0; segment < 10; ++segment) {
      modelGauge[i][segment] = lv_obj_create(modelRows[i]);
      lv_obj_set_pos(modelGauge[i][segment], 42 + segment * 18, 29);
      lv_obj_set_size(modelGauge[i][segment], 14, 5);
      lv_obj_set_style_bg_color(modelGauge[i][segment], lv_color_hex(kRaised), 0);
      lv_obj_set_style_border_width(modelGauge[i][segment], 0, 0);
      lv_obj_set_style_radius(modelGauge[i][segment], 1, 0);
    }
  }
  createGame(pages[0]);
  createAlertOverlay(screen);
  showPage(0);
}

uint32_t attentionColor(uint8_t attention) {
  return attention >= 2 ? kDanger : attention == 1 ? kWarning : kOK;
}

const char *attentionText(uint8_t attention) {
  return attention >= 2 ? "CRITICAL" : attention == 1 ? "WARNING" : "OK";
}

const char *providerDisplayName(const char *id) {
  if (!strcmp(id, "claude-code")) return "*  CLAUDE";
  if (!strcmp(id, "codex")) return "</> CODEX";
  if (!strcmp(id, "gemini-cli")) return "+  GEMINI";
  if (!strcmp(id, "api-accounts")) return "@  APIS";
  return id;
}

int findProvider(const char *id) {
  for (size_t i = 0; i < providerCount; ++i) if (!strcmp(providers[i].id, id)) return i;
  return -1;
}

void compactTokens(int64_t tokens, char *output, size_t capacity) {
  if (tokens >= 1000000000LL) snprintf(output, capacity, "%.1fB", tokens / 1000000000.0);
  else if (tokens >= 1000000LL) snprintf(output, capacity, "%.1fM", tokens / 1000000.0);
  else if (tokens >= 1000LL) snprintf(output, capacity, "%.1fK", tokens / 1000.0);
  else snprintf(output, capacity, "%" PRId64, tokens);
}

uint64_t estimatedEpochMs() {
  if (!snapshotEpochMs || !lastSnapshotMs) return 0;
  return snapshotEpochMs + static_cast<uint64_t>(millis() - lastSnapshotMs);
}

void formatCountdown(uint64_t targetEpochMs, char *output, size_t capacity) {
  const uint64_t nowEpochMs = estimatedEpochMs();
  if (!targetEpochMs || !nowEpochMs) {
    strlcpy(output, "--", capacity);
    return;
  }
  if (targetEpochMs <= nowEpochMs) {
    strlcpy(output, "NOW", capacity);
    return;
  }
  const uint64_t minutes = (targetEpochMs - nowEpochMs + 59999) / 60000;
  if (minutes < 60) snprintf(output, capacity, "%" PRIu64 "M", minutes);
  else if (minutes < 24 * 60)
    snprintf(output, capacity, "%" PRIu64 "H %02" PRIu64 "M", minutes / 60, minutes % 60);
  else
    snprintf(output, capacity, "%" PRIu64 "D %02" PRIu64 "H", minutes / 1440, (minutes % 1440) / 60);
}

uint32_t alertColor(uint8_t threshold) {
  if (threshold <= 5) return kDanger;
  if (threshold <= 25) return kWarning;
  if (threshold <= 50) return kCoral;
  return kOK;
}

const char *alertHeadline(uint8_t threshold) {
  if (threshold <= 5) return "ALMOST EMPTY";
  if (threshold <= 25) return "RUNNING LOW";
  if (threshold <= 50) return "HALFWAY";
  if (threshold <= 75) return "ON TRACK";
  return "FULL TANK";
}

const char *alertMessage(uint8_t threshold) {
  if (threshold <= 5) return "This window is about to run out.";
  if (threshold <= 25) return "Plan the next prompts.";
  if (threshold <= 50) return "Half of this window remains.";
  if (threshold <= 75) return "A quarter of the window was used.";
  return "A new usage window is ready.";
}

AlertTracker &trackerFor(const ProviderState &provider) {
  for (AlertTracker &tracker : alertTrackers) {
    if (tracker.initialized && !strcmp(tracker.id, provider.id)) {
      if (strcmp(tracker.window, provider.window)) {
        strlcpy(tracker.window, provider.window, sizeof(tracker.window));
        tracker.lowestRemaining = 101;
        tracker.resetEpochMs = 0;
        tracker.firedMask = 0;
        tracker.observed = false;
      }
      return tracker;
    }
  }
  for (AlertTracker &tracker : alertTrackers) {
    if (!tracker.initialized) {
      strlcpy(tracker.id, provider.id, sizeof(tracker.id));
      strlcpy(tracker.window, provider.window, sizeof(tracker.window));
      tracker.initialized = true;
      return tracker;
    }
  }
  return alertTrackers[0];
}

void showDeskAlert(const ProviderState &provider, uint8_t threshold) {
  if (activeAlertThreshold && activeAlertThreshold < threshold &&
      !lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) return;
  const uint32_t color = alertColor(threshold);
  activeAlertThreshold = threshold;
  alertShownAt = millis();
  lv_obj_set_style_border_color(alertOverlay, lv_color_hex(color), 0);
  lv_obj_set_style_bg_color(alertOverlay, lv_color_hex(threshold <= 5 ? 0x150506 : 0x0C0908), 0);
  char providerText[64];
  snprintf(providerText, sizeof(providerText), "%s  /  %s WINDOW",
           providerDisplayName(provider.id), !strcmp(provider.window, "weekly") ? "WEEKLY" : "5H");
  lv_label_set_text(alertProviderLabel, providerText);
  char percentText[16];
  snprintf(percentText, sizeof(percentText), "%.0f%%", max(0.0f, provider.remaining));
  lv_label_set_text(alertPercentLabel, percentText);
  lv_obj_set_style_text_color(alertPercentLabel, lv_color_hex(color), 0);
  lv_label_set_text(alertHeadlineLabel, alertHeadline(threshold));
  lv_obj_set_style_text_color(alertHeadlineLabel, lv_color_hex(color), 0);
  lv_label_set_text(alertMessageLabel, alertMessage(threshold));
  lv_label_set_text(alertDismissLabel, threshold <= 5 ? "TAP TO DISMISS" : "TAP OR WAIT");
  const int lit = constrain(static_cast<int>(ceil(provider.remaining / 6.25f)), 0, 16);
  for (int i = 0; i < 16; ++i) {
    lv_obj_set_style_bg_color(alertSegments[i], lv_color_hex(i < lit ? color : kRaised), 0);
  }
  for (int row = 0; row < 6; ++row) {
    for (int col = 0; col < 8; ++col) {
      if (kClawd[row][col] == 1) {
        lv_obj_set_style_bg_color(alertMascotPixels[row][col], lv_color_hex(color), 0);
      } else if (kClawd[row][col] == 2) {
        lv_obj_set_style_bg_color(alertMascotPixels[row][col], lv_color_hex(kPanel), 0);
      }
    }
  }
  lv_obj_remove_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN);
  lv_obj_move_foreground(alertOverlay);
}

void evaluateDeskAlerts() {
  int chosenProvider = -1;
  int chosenThreshold = 101;
  for (size_t i = 0; i < providerCount; ++i) {
    ProviderState &provider = providers[i];
    if (provider.remaining < 0) continue;
    AlertTracker &tracker = trackerFor(provider);
    const uint64_t resetDifference = provider.resetEpochMs > tracker.resetEpochMs
      ? provider.resetEpochMs - tracker.resetEpochMs
      : tracker.resetEpochMs - provider.resetEpochMs;
    const bool resetBoundaryChanged = tracker.observed && provider.resetEpochMs &&
      tracker.resetEpochMs && resetDifference > kResetBoundaryToleranceMs;
    const bool inferredReset = tracker.observed && !provider.resetEpochMs &&
      (provider.remaining >= 99.5f || provider.remaining - tracker.lowestRemaining >= 20.0f);
    if (resetBoundaryChanged || inferredReset) {
      tracker.firedMask = 0;
      tracker.lowestRemaining = provider.remaining;
    }
    int crossing = 101;
    int deepest = 101;
    for (size_t level = 0; level < alertThresholdCount; ++level) {
      deepest = min(deepest, static_cast<int>(alertThresholds[level]));
      if (provider.remaining <= alertThresholds[level]) {
        if (tracker.observed && !(tracker.firedMask & (1U << level)))
          crossing = min(crossing, static_cast<int>(alertThresholds[level]));
        tracker.firedMask |= 1U << level;
      }
    }
    if (!tracker.observed) {
      if (provider.remaining >= 99.5f) {
        for (size_t level = 0; level < alertThresholdCount; ++level)
          if (alertThresholds[level] == 100) crossing = 100;
      } else if (deepest <= 100 && provider.remaining <= deepest) {
        crossing = deepest;
      }
    }
    tracker.observed = true;
    tracker.resetEpochMs = provider.resetEpochMs;
    tracker.lowestRemaining = min(tracker.lowestRemaining, provider.remaining);
    if (crossing < chosenThreshold) {
      chosenProvider = i;
      chosenThreshold = crossing;
    }
  }
  if (chosenProvider >= 0) showDeskAlert(providers[chosenProvider], chosenThreshold);
}

void updateGame() {
  const uint32_t now = millis();
  if (!gameLastTick) gameLastTick = now;
  const float delta = min(0.1f, (now - gameLastTick) / 1000.0f);
  gameLastTick = now;

  int gameProvider = findProvider("claude-code");
  if (gameProvider < 0 && providerCount) gameProvider = 0;
  const float remaining = gameProvider >= 0 && providers[gameProvider].remaining >= 0
    ? providers[gameProvider].remaining : 100.0f;
  const float used = constrain(100.0f - remaining, 0.0f, 100.0f);
  const float difficulty = used / 100.0f;
  const int level = 1 + min(4, static_cast<int>(difficulty * 5.0f));
  const float speed = 40.0f + difficulty * 72.0f;
  const float obstacleGap = 145.0f - difficulty * 63.0f;
  const float jumpDurationMs = 1200.0f - difficulty * 600.0f;
  gameOver = remaining <= 0.5f;
  if (gameOver) {
    jumpActive = false;
    jumpElapsedMs = 0;
  }

  if (!runnerEnabled) {
    jumpActive = false;
    jumpElapsedMs = 0;
    lv_obj_set_y(gameMascot, 32);
    lv_label_set_text(gameStatus, "RUNNER DISABLED IN SETTINGS");
    setGameSprite(kGaitA, kMuted);
    return;
  }

  if (runnerCrashed) {
    if (now - runnerCrashedAt >= 1200) {
      gameObstacleX[0] = 190;
      for (int i = 1; i < 4; ++i) gameObstacleX[i] = gameObstacleX[i - 1] + obstacleGap;
      runnerCrashed = false;
      jumpElapsedMs = 0;
      gameScore = 0;
    } else {
      lv_obj_set_y(gameMascot, 32);
      setGameSprite(kDead, kDanger);
      lv_label_set_text(gameStatus, "CRASH!  TAP TO RESTART");
      lv_obj_set_style_text_color(gameStatus, lv_color_hex(kDanger), 0);
      return;
    }
  }

  constexpr float mascotCenterX = 49.0f;
  float nearestObstacleX = 1000;
  for (int i = 0; i < 4; ++i) {
    if (!gameOver) gameObstacleX[i] -= speed * delta;
    if (gameObstacleX[i] < -24) {
      float furthest = gameObstacleX[0];
      for (float x : gameObstacleX) furthest = max(furthest, x);
      gameObstacleX[i] = furthest + obstacleGap + (i % 2) * 10;
      gameScore += 10;
    }
    lv_obj_set_x(gameObstacles[i], static_cast<int>(gameObstacleX[i]));
    if (gameObstacleX[i] > mascotCenterX) nearestObstacleX = min(nearestObstacleX, gameObstacleX[i]);
  }
  const float timeToImpactSeconds = (nearestObstacleX - mascotCenterX) / speed;
  const float idealJumpLeadSeconds = jumpDurationMs / 2000.0f;
  bool autoJumpStartedThisFrame = false;
  if (!gameOver && timeToImpactSeconds <= idealJumpLeadSeconds && !jumpActive) {
    jump();
    autoJumpStartedThisFrame = jumpActive;
  }

  float jumpHeight = 0;
  if (jumpActive) {
    if (!autoJumpStartedThisFrame) jumpElapsedMs += delta * 1000.0f;
    const float progress = jumpElapsedMs / jumpDurationMs;
    if (progress >= 1) {
      jumpActive = false;
      jumpElapsedMs = 0;
    } else {
      jumpHeight = sin(progress * PI) * 30.0f;
    }
  }
  lv_obj_set_y(gameMascot, 32 - static_cast<int>(jumpHeight));

  if (!gameOver) {
    const int mascotLeft = 42;
    const int mascotRight = 58;
    const int mascotBottom = 62 - static_cast<int>(jumpHeight);
    for (int i = 0; i < 4; ++i) {
      const int obstacleX = static_cast<int>(gameObstacleX[i]);
      const int obstacleWidth = i % 2 ? 8 : 10;
      const int obstacleTop = i % 2 ? 48 : 44;
      const bool overlapsX = obstacleX < mascotRight && obstacleX + obstacleWidth > mascotLeft;
      if (overlapsX && mascotBottom > obstacleTop + 2) {
        runnerCrashed = true;
        runnerCrashedAt = now;
        jumpActive = false;
        jumpElapsedMs = 0;
        break;
      }
    }
  }

  const uint32_t tint = remaining <= 5 ? kDanger : remaining <= 25 ? kWarning : kCoral;
  for (int i = 0; i < 4; ++i) {
    const uint32_t obstacleTint = remaining <= 5 ? kDanger : remaining <= 25 ? kWarning : kOK;
    lv_obj_set_style_bg_color(gameObstacles[i], lv_color_hex(obstacleTint), 0);
    if (lv_obj_get_child_count(gameObstacles[i])) {
      lv_obj_set_style_bg_color(lv_obj_get_child(gameObstacles[i], 0), lv_color_hex(obstacleTint), 0);
    }
  }
  if (gameOver || runnerCrashed) setGameSprite(kDead, kDanger);
  else setGameSprite((now / 90) % 2 ? kGaitA : kGaitB, tint);

  gameDistance += speed * delta;
  for (int i = 0; i < 40; ++i) {
    int x = (i * 12 - static_cast<int>(gameDistance)) % 480;
    if (x < 0) x += 480;
    lv_obj_set_x(gameGround[i], x);
  }
  char status[80];
  if (gameOver) snprintf(status, sizeof(status), "GAME OVER  /  NEW RUN AFTER RESET");
  else if (runnerCrashed) snprintf(status, sizeof(status), "CRASH!  TAP TO RESTART");
  else snprintf(status, sizeof(status), "S%05lu  L%d  %.0f%% LEFT", static_cast<unsigned long>(gameScore), level, remaining);
  lv_label_set_text(gameStatus, status);
  lv_obj_set_style_text_color(gameStatus, lv_color_hex(gameOver ? kDanger : kMuted), 0);
}

void updateAlertAnimation() {
  if (!activeAlertThreshold || lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) return;
  const uint32_t age = millis() - alertShownAt;
  if (activeAlertThreshold > 5 && age >= 4500) {
    dismissDeskAlert();
    return;
  }
  const uint8_t pulse = 80 + static_cast<uint8_t>((sin(millis() / 180.0f) + 1) * 70);
  lv_obj_set_style_border_opa(alertOverlay, pulse, 0);
  const int tremor = activeAlertThreshold <= 5 ? (millis() / 45) % 2 : 0;
  for (int row = 0; row < 6; ++row)
    for (int col = 0; col < 8; ++col)
      lv_obj_set_x(alertMascotPixels[row][col], 28 + col * 10 + tremor);
}

void refreshUI() {
  int displayProviders[2] = {findProvider("claude-code"), findProvider("codex")};
  for (int slot = 0; slot < 2; ++slot) {
    if (displayProviders[slot] < 0) {
      for (size_t candidate = 0; candidate < providerCount; ++candidate) {
        if (static_cast<int>(candidate) != displayProviders[1 - slot]) {
          displayProviders[slot] = candidate;
          break;
        }
      }
    }
    if (displayProviders[slot] < 0) {
      lv_label_set_text(providerNames[slot], "NO PROVIDER");
      lv_label_set_text(providerValues[slot], "--");
      lv_label_set_text(providerCaptions[slot], "WAITING FOR DATA");
      lv_label_set_text(providerDetails[slot], "");
      lv_label_set_text(providerStatuses[slot], "NO DATA");
      for (int segment = 0; segment < 10; ++segment)
        lv_obj_set_style_bg_color(providerGauge[slot][segment], lv_color_hex(kRaised), 0);
      continue;
    }
    ProviderState &provider = providers[displayProviders[slot]];
    char value[24];
    char detail[80];
    lv_label_set_text(providerNames[slot], providerDisplayName(provider.id));
    if (provider.remaining >= 0) {
      snprintf(value, sizeof(value), "%.0f%%", provider.remaining);
      lv_label_set_text(providerCaptions[slot],
                        !strcmp(provider.window, "weekly") ? "OF WEEKLY LIMIT LEFT" : "OF SESSION LIMIT LEFT");
    } else {
      compactTokens(provider.tokens, value, sizeof(value));
      lv_label_set_text(providerCaptions[slot], "CURRENT SESSION  /  NO CAP");
    }
    lv_label_set_text(providerValues[slot], value);
    lv_obj_set_style_text_color(providerValues[slot], lv_color_hex(
      provider.remaining >= 0 ? attentionColor(provider.attention) : kText), 0);
    char tokenText[24];
    compactTokens(provider.tokens, tokenText, sizeof(tokenText));
    if (provider.burn > 0) snprintf(detail, sizeof(detail), "%s TOKENS  /  +%.1f%%/H", tokenText, provider.burn);
    else snprintf(detail, sizeof(detail), "%s TOKENS  /  STABLE", tokenText);
    lv_label_set_text(providerDetails[slot], detail);
    char status[40];
    snprintf(status, sizeof(status), "[%s]  %s", attentionText(provider.attention), provider.refresh);
    lv_label_set_text(providerStatuses[slot], status);
    lv_obj_set_style_text_color(providerStatuses[slot], lv_color_hex(attentionColor(provider.attention)), 0);
    const int lit = provider.remaining >= 0 ? constrain(static_cast<int>(ceil(provider.remaining / 10.0f)), 0, 10) : 0;
    for (int segment = 0; segment < 10; ++segment) {
      lv_obj_set_style_bg_color(providerGauge[slot][segment],
        lv_color_hex(segment < lit ? attentionColor(provider.attention) : kRaised), 0);
    }
  }

  const ProviderState *primary = providerCount ? &providers[0] : nullptr;
  char hero[24] = "--%";
  char resetCountdown[24] = "--";
  char exhaustCountdown[24] = "--";
  char detail[96] = "I'LL FORECAST RISK AS DATA ARRIVES.";
  char status[96] = "USE NOTCHAGENT FOR A FEW MINUTES.";
  char windowMetric[24] = "--";
  char resetMetric[24] = "UNKNOWN";
  char paceMetric[24] = "--";
  const uint64_t nowEpochMs = estimatedEpochMs();
  const bool hasGauge = primary && primary->remaining >= 0;
  const bool hasBurn = hasGauge && primary->burn > 0.05f;
  const bool hasReset = primary && primary->resetEpochMs > nowEpochMs;
  const bool runsOut = hasBurn && hasReset && primary->exhaustEpochMs > nowEpochMs &&
    primary->exhaustEpochMs < primary->resetEpochMs;
  if (primary) lv_label_set_text(burnProvider, providerDisplayName(primary->id));
  else lv_label_set_text(burnProvider, "NO PROVIDER");
  if (hasGauge) {
    snprintf(hero, sizeof(hero), "%.0f%%", primary->remaining);
    formatCountdown(primary->resetEpochMs, resetCountdown, sizeof(resetCountdown));
    formatCountdown(primary->exhaustEpochMs, exhaustCountdown, sizeof(exhaustCountdown));
    strlcpy(windowMetric, !strcmp(primary->window, "weekly") ? "WEEKLY" : "5H SESSION", sizeof(windowMetric));
    strlcpy(resetMetric, hasReset ? resetCountdown : "UNKNOWN", sizeof(resetMetric));
    if (hasBurn) snprintf(paceMetric, sizeof(paceMetric), "+%.1f%%/H", primary->burn);
    else strlcpy(paceMetric, "STABLE", sizeof(paceMetric));
    if (!hasReset) {
      lv_label_set_text(burnVerdict, "RESET TIME UNKNOWN");
      snprintf(status, sizeof(status), "%s DID NOT REPORT A RESET TIME.", providerDisplayName(primary->id));
      snprintf(detail, sizeof(detail), "%.0f%% LEFT. I'LL KEEP WATCHING YOUR PACE.", primary->remaining);
    } else if (runsOut) {
      lv_label_set_text(burnVerdict, "YES  /  SLOW DOWN");
      snprintf(status, sizeof(status), "LIMIT ENDS IN %s. REDUCE USAGE.", exhaustCountdown);
      strlcpy(detail, "PAUSE HEAVY TASKS UNTIL THE LIMIT RESETS.", sizeof(detail));
    } else if (hasBurn) {
      const float hoursToReset = (primary->resetEpochMs - nowEpochMs) / 3600000.0f;
      const float projectedLeft = max(0.0f, primary->remaining - primary->burn * hoursToReset);
      lv_label_set_text(burnVerdict, "NO  /  YOU'RE SAFE");
      snprintf(status, sizeof(status), "AT THIS PACE, ~%.0f%% WILL REMAIN.", projectedLeft);
      strlcpy(detail, "KEEP WORKING. I'LL WARN YOU IF RISK RISES.", sizeof(detail));
    } else {
      lv_label_set_text(burnVerdict, "NO  /  YOU'RE SAFE");
      strlcpy(status, "NO ACTIVE BURN DETECTED.", sizeof(status));
      strlcpy(detail, "KEEP WORKING. I'LL WARN YOU IF RISK APPEARS.", sizeof(detail));
    }
  } else {
    lv_label_set_text(burnVerdict, "LEARNING YOUR PACE");
  }
  lv_label_set_text(burnHero, hero);
  lv_label_set_text(burnDetail, detail);
  lv_label_set_text(burnStatus, status);
  lv_label_set_text(burnMetricValues[0], windowMetric);
  lv_label_set_text(burnMetricValues[1], resetMetric);
  lv_label_set_text(burnMetricValues[2], paceMetric);
  const uint32_t burnTint = !hasGauge ? kMuted : !hasReset ? kWarning : runsOut ? kDanger : kOK;
  const uint32_t runwayTint = hasGauge ? attentionColor(primary->attention) : kMuted;
  lv_obj_set_style_text_color(burnHero, lv_color_hex(runwayTint), 0);
  lv_obj_set_style_text_color(burnVerdict, lv_color_hex(burnTint), 0);
  lv_obj_set_style_text_color(burnStatus, lv_color_hex(burnTint), 0);
  lv_obj_set_style_border_color(burnVerdictPanel, lv_color_hex(burnTint), 0);
  lv_obj_set_style_border_width(burnVerdictPanel, 2, 0);
  lv_obj_set_style_text_color(burnMetricValues[0], lv_color_hex(kText), 0);
  lv_obj_set_style_text_color(burnMetricValues[1], lv_color_hex(hasReset ? kText : kWarning), 0);
  lv_obj_set_style_text_color(burnMetricValues[2], lv_color_hex(hasBurn ? kCoral : hasGauge ? kOK : kMuted), 0);
  const int litRunway = hasGauge ? constrain(static_cast<int>(ceil(primary->remaining / 5.0f)), 0, 20) : 0;
  for (int segment = 0; segment < 20; ++segment) {
    lv_obj_set_style_bg_color(burnGauge[segment],
      lv_color_hex(segment < litRunway ? runwayTint : kRaised), 0);
  }

  int64_t peak = 1;
  int peakHour = 0;
  int64_t total = 0;
  int64_t periodTotals[4] = {};
  for (int i = 0; i < 24; ++i) {
    total += rhythm[i];
    periodTotals[i / 6] += rhythm[i];
    if (rhythm[i] > peak) { peak = rhythm[i]; peakHour = i; }
  }
  char totalText[24];
  compactTokens(total, totalText, sizeof(totalText));
  int strongestPeriod = 0;
  for (int period = 1; period < 4; ++period)
    if (periodTotals[period] > periodTotals[strongestPeriod]) strongestPeriod = period;
  const char *periodNames[4] = {"NIGHT", "MORNING", "AFTERNOON", "EVENING"};
  char peakText[16] = "--";
  if (total > 0) snprintf(peakText, sizeof(peakText), "%02d:00", peakHour);
  lv_label_set_text(rhythmMetricValues[0], peakText);
  lv_label_set_text(rhythmMetricValues[1], total > 0 ? totalText : "0");
  lv_label_set_text(rhythmMetricValues[2], total > 0 ? periodNames[strongestPeriod] : "WAITING");
  lv_obj_set_style_text_color(rhythmMetricValues[0], lv_color_hex(total > 0 ? kOK : kMuted), 0);
  lv_obj_set_style_text_color(rhythmMetricValues[1], lv_color_hex(total > 0 ? kText : kMuted), 0);
  lv_obj_set_style_text_color(rhythmMetricValues[2], lv_color_hex(total > 0 ? kCoral : kMuted), 0);
  for (int i = 0; i < 24; ++i) {
    const int height = max(2, static_cast<int>(rhythm[i] * 88 / peak));
    lv_obj_set_y(rhythmBars[i], 195 - height);
    lv_obj_set_height(rhythmBars[i], height);
    lv_obj_set_style_bg_color(rhythmBars[i], lv_color_hex(
      total == 0 ? kRaised : i == peakHour ? kOK : kCoral), 0);
  }

  int64_t totalModelTokens = 0;
  int64_t peakModelTokens = 1;
  for (size_t i = 0; i < modelCount; ++i) {
    totalModelTokens += models[i].tokens;
    peakModelTokens = max(peakModelTokens, models[i].tokens);
  }
  char totalModelText[24];
  char modelSummaryText[64];
  compactTokens(totalModelTokens, totalModelText, sizeof(totalModelText));
  if (modelCount) snprintf(modelSummaryText, sizeof(modelSummaryText), "%u TRACKED  /  %s TOKENS",
                           static_cast<unsigned>(modelCount), totalModelText);
  else strlcpy(modelSummaryText, "0 TRACKED  /  WAITING", sizeof(modelSummaryText));
  lv_label_set_text(modelSummary, modelSummaryText);
  for (int i = 0; i < 4; ++i) {
    char modelTokens[24] = "--";
    char modelStatus[32] = "NO DATA";
    uint32_t statusTint = kMuted;
    int litUsage = 0;
    if (i < static_cast<int>(modelCount)) {
      compactTokens(models[i].tokens, modelTokens, sizeof(modelTokens));
      if (!strcmp(models[i].status, "ok")) {
        statusTint = kOK;
        if (models[i].latency >= 0) snprintf(modelStatus, sizeof(modelStatus), "OK  %dms", models[i].latency);
        else strlcpy(modelStatus, "OK", sizeof(modelStatus));
      } else if (!strcmp(models[i].status, "limited")) {
        statusTint = kWarning;
        strlcpy(modelStatus, "LIMITED", sizeof(modelStatus));
      } else if (!strcmp(models[i].status, "error")) {
        statusTint = kDanger;
        strlcpy(modelStatus, "ERROR", sizeof(modelStatus));
      } else {
        strlcpy(modelStatus, "NOT PROBED", sizeof(modelStatus));
      }
      litUsage = models[i].tokens > 0
        ? constrain(static_cast<int>(ceil(models[i].tokens * 10.0 / peakModelTokens)), 1, 10) : 0;
      lv_label_set_text(modelLabels[i], models[i].name);
      lv_obj_set_style_text_color(modelLabels[i], lv_color_hex(kText), 0);
    } else {
      lv_label_set_text(modelLabels[i], "NO MODEL");
      lv_obj_set_style_text_color(modelLabels[i], lv_color_hex(kMuted), 0);
    }
    lv_label_set_text(modelTokenLabels[i], modelTokens);
    lv_label_set_text(modelStatusLabels[i], modelStatus);
    lv_obj_set_style_text_color(modelStatusLabels[i], lv_color_hex(statusTint), 0);
    lv_obj_set_style_border_color(modelRows[i], lv_color_hex(statusTint), 0);
    for (int segment = 0; segment < 10; ++segment)
      lv_obj_set_style_bg_color(modelGauge[i][segment],
        lv_color_hex(segment < litUsage ? kCoral : kRaised), 0);
  }

}

void clearData() {
  dismissDeskAlert();
  providerCount = modelCount = 0;
  burnPointCount = 0;
  memset(rhythm, 0, sizeof(rhythm));
  dataCleared = true;
  refreshUI();
}

bool parseSnapshot(const uint8_t *payload, size_t length) {
  JsonDocument document;
  const DeserializationError error = deserializeJson(document, payload, length);
  if (error || document["product"] != "NotchAgent Desk" || document["protocolMajor"] != 1) return false;
  providerCount = modelCount = 0;
  overallAttention = document["overallAttention"] | 0;
  paused = document["isPaused"] | false;
  runnerEnabled = document["runnerEnabled"] | true;
  snapshotEpochMs = document["generatedAt"].is<uint64_t>()
    ? document["generatedAt"].as<uint64_t>() : 0;
  const char *ambientPage = document["ambientRecommendation"]["page"] | "";
  const char *ambientReason = document["ambientRecommendation"]["reason"] | "";
  ambientStatus[0] = '\0';

  uint8_t incomingThresholds[5] = {};
  size_t incomingCount = 0;
  const bool hasThresholds = document["alertThresholds"].is<JsonArray>();
  for (int value : document["alertThresholds"].as<JsonArray>()) {
    const uint8_t clamped = constrain(value, 1, 100);
    bool duplicate = false;
    for (size_t i = 0; i < incomingCount; ++i) duplicate |= incomingThresholds[i] == clamped;
    if (!duplicate && incomingCount < 5) incomingThresholds[incomingCount++] = clamped;
  }
  for (size_t i = 0; i < incomingCount; ++i)
    for (size_t j = i + 1; j < incomingCount; ++j)
      if (incomingThresholds[j] > incomingThresholds[i]) {
        const uint8_t swap = incomingThresholds[i];
        incomingThresholds[i] = incomingThresholds[j];
        incomingThresholds[j] = swap;
      }
  bool thresholdsChanged = hasThresholds && incomingCount != alertThresholdCount;
  if (hasThresholds) {
    for (size_t i = 0; i < incomingCount; ++i) {
      if (incomingThresholds[i] != alertThresholds[i]) thresholdsChanged = true;
      alertThresholds[i] = incomingThresholds[i];
    }
    alertThresholdCount = incomingCount;
  }
  if (thresholdsChanged) {
    memset(alertTrackers, 0, sizeof(alertTrackers));
    dismissDeskAlert();
  }

  for (JsonObject item : document["providers"].as<JsonArray>()) {
    if (providerCount >= 8) break;
    ProviderState &state = providers[providerCount++];
    strlcpy(state.id, item["id"] | "unknown", sizeof(state.id));
    strlcpy(state.refresh, item["refreshState"] | "idle", sizeof(state.refresh));
    strlcpy(state.window, item["window"] | "", sizeof(state.window));
    state.remaining = item["remainingPercent"].is<float>() ? item["remainingPercent"].as<float>() : -1;
    state.burn = item["burnPercentPerHour"].is<float>() ? item["burnPercentPerHour"].as<float>() : -1;
    state.tokens = max<int64_t>(0, item["tokens"].as<int64_t>());
    state.attention = item["attention"] | 0;
    state.resetEpochMs = item["resetsAt"].is<uint64_t>() ? item["resetsAt"].as<uint64_t>() : 0;
    state.exhaustEpochMs = item["exhaustsAt"].is<uint64_t>() ? item["exhaustsAt"].as<uint64_t>() : 0;
  }
  memset(rhythm, 0, sizeof(rhythm));
  burnPointCount = 0;
  for (JsonObject item : document["burnHistory"].as<JsonArray>()) {
    if (burnPointCount >= 48) break;
    burnAgeSeconds[burnPointCount] = max(0.0f, item["ageSeconds"].as<float>());
    burnUsedPercent[burnPointCount] = constrain(item["usedPercent"].as<float>(), 0.0f, 100.0f);
    ++burnPointCount;
  }
  for (JsonObject item : document["rhythm"].as<JsonArray>()) {
    const int hour = item["hour"] | -1;
    if (hour >= 0 && hour < 24) rhythm[hour] = max<int64_t>(0, item["tokens"].as<int64_t>());
  }
  for (JsonObject item : document["models"].as<JsonArray>()) {
    if (modelCount >= 8) break;
    ModelState &state = models[modelCount++];
    strlcpy(state.name, item["name"] | "unknown", sizeof(state.name));
    strlcpy(state.status, item["status"] | "", sizeof(state.status));
    state.tokens = max<int64_t>(0, item["tokens"].as<int64_t>());
    state.latency = item["latencyMs"].is<int>() ? item["latencyMs"].as<int>() : -1;
  }
  lastSnapshotMs = millis();
  dataCleared = false;
  refreshUI();
  evaluateDeskAlerts();
  if ((!lastUserInteractionAt || millis() - lastUserInteractionAt >= 30000) &&
      lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) {
    int recommendedPage = -1;
    if (!strcmp(ambientPage, "now")) recommendedPage = 0;
    else if (!strcmp(ambientPage, "burn")) recommendedPage = 1;
    else if (!strcmp(ambientPage, "rhythm")) recommendedPage = 2;
    else if (!strcmp(ambientPage, "models")) recommendedPage = 3;
    if (recommendedPage >= 0) {
      navigatePage(recommendedPage);
      snprintf(ambientStatus, sizeof(ambientStatus), "AUTO / %s",
               ambientReason[0] ? ambientReason : ambientPage);
    }
  }
  return true;
}

void handleFrame(const desk_protocol::FrameView &frame) {
  if (frame.type == desk_protocol::Hello) {
    JsonDocument hello;
    if (deserializeJson(hello, frame.payload, frame.payloadLength) ||
        hello["product"] != "NotchAgent Desk" || hello["protocolMajor"] != 1) return;
    JsonDocument acknowledgement;
    acknowledgement["product"] = "NotchAgent Desk";
    acknowledgement["protocolMajor"] = 1;
    acknowledgement["protocolMinor"] = DESK_PROTOCOL_MINOR;
    acknowledgement["nonce"] = hello["nonce"].as<uint32_t>();
    acknowledgement["firmwareVersion"] = DESK_FW_VERSION;
    const size_t acknowledgementLength = serializeJson(acknowledgement, decodedBuffer, DESK_MAX_PAYLOAD + 32);
    desk_protocol::writeFrame(Serial, desk_protocol::HelloAcknowledgement, ++outgoingSequence,
                              decodedBuffer, acknowledgementLength, packetBuffer,
                              DESK_MAX_PAYLOAD + 32, encodedBuffer, DESK_MAX_PAYLOAD + 128);
    hostRecognized = true;
    ++handshakeCount;
    lv_label_set_text(connectionLabel, "MAC CONNECTED");
  } else if (frame.type == desk_protocol::Snapshot) {
    if (hostRecognized && parseSnapshot(frame.payload, frame.payloadLength)) {
      if (paused) lv_label_set_text(connectionLabel, "PAUSED");
      else lv_label_set_text(connectionLabel, ambientStatus[0] ? ambientStatus : "UPDATED NOW");
    }
  }
}

void pollSerial() {
  while (Serial.available()) {
    const uint8_t byte = Serial.read();
    if (byte == 0) {
      if (packetLength) {
        desk_protocol::FrameView frame;
        if (desk_protocol::decodeFrame(packetBuffer, packetLength, decodedBuffer,
                                       DESK_MAX_PAYLOAD + 32, frame)) handleFrame(frame);
        else ++invalidFrameCount;
      }
      packetLength = 0;
    } else if (packetLength < DESK_MAX_PAYLOAD + 128) {
      packetBuffer[packetLength++] = byte;
    } else {
      packetLength = 0;
    }
  }
}

const char *resetReasonName() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power_on";
    case ESP_RST_SW: return "software";
    case ESP_RST_PANIC: return "panic";
    case ESP_RST_INT_WDT: return "interrupt_watchdog";
    case ESP_RST_TASK_WDT: return "task_watchdog";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_USB: return "usb";
    default: return "other";
  }
}

void sendDeviceTelemetry() {
  if (!hostRecognized) return;
  JsonDocument document;
  document["firmwareVersion"] = DESK_FW_VERSION;
  document["uptimeSeconds"] = millis() / 1000ULL;
  document["freeHeapBytes"] = ESP.getFreeHeap();
  document["minimumFreeHeapBytes"] = ESP.getMinFreeHeap();
  document["framesPerSecond"] = measuredFPS;
  document["resetReason"] = resetReasonName();
  document["invalidFrameCount"] = invalidFrameCount;
  document["handshakeCount"] = handshakeCount;
  document["touchCount"] = touch.touchCount();
  document["touchInterruptCount"] = touch.interruptCount();
  document["touchReadErrorCount"] = touch.readErrorCount();
  document["touchPollAttemptCount"] = touch.pollAttemptCount();
  document["touchPollTouchCount"] = touch.pollTouchCount();
  document["touchControllerPresent"] = touch.controllerPresent();
  document["lastTouchLatencyMs"] = touch.lastLatencyMicros() / 1000.0f;
  document["maximumTouchLatencyMs"] = touch.maxLatencyMicros() / 1000.0f;
  const size_t length = serializeJson(document, decodedBuffer, DESK_MAX_PAYLOAD + 32);
  desk_protocol::writeFrame(Serial, desk_protocol::DeviceTelemetry, ++outgoingSequence,
                            decodedBuffer, length, packetBuffer, DESK_MAX_PAYLOAD + 32,
                            encodedBuffer, DESK_MAX_PAYLOAD + 128);
}

void updateFreshness() {
  if (!lastSnapshotMs) return;
  // Pause intentionally freezes the last valid snapshot; it is not stale and
  // must never be erased merely because refreshes are suspended.
  if (paused) {
    lv_label_set_text(connectionLabel, "PAUSED");
    ledcWrite(DESK_TFT_BACKLIGHT, 150);
    return;
  }
  const uint32_t age = millis() - lastSnapshotMs;
  if (age > DESK_CLEAR_MS && !dataCleared) {
    clearData();
    lv_label_set_text(connectionLabel, "DATA CLEARED");
  } else if (age > DESK_STALE_MS) {
    lv_label_set_text(connectionLabel, "STALE");
    ledcWrite(DESK_TFT_BACKLIGHT, 70);
  } else {
    ledcWrite(DESK_TFT_BACKLIGHT, 210);
  }
}

}  // namespace

void setup() {
  Serial.setRxBufferSize(DESK_MAX_PAYLOAD + 128);
  Serial.begin(DESK_SERIAL_BAUD);
  packetBuffer = static_cast<uint8_t *>(heap_caps_malloc(DESK_MAX_PAYLOAD + 128, MALLOC_CAP_SPIRAM));
  decodedBuffer = static_cast<uint8_t *>(heap_caps_malloc(DESK_MAX_PAYLOAD + 32, MALLOC_CAP_SPIRAM));
  encodedBuffer = static_cast<uint8_t *>(heap_caps_malloc(DESK_MAX_PAYLOAD + 128, MALLOC_CAP_SPIRAM));
  if (!packetBuffer || !decodedBuffer || !encodedBuffer) while (true) delay(1000);

  Arduino_DataBus *bus = new Arduino_ESP32QSPI(DESK_TFT_CS, DESK_TFT_SCK, DESK_TFT_D0,
                                                DESK_TFT_D1, DESK_TFT_D2, DESK_TFT_D3);
  Arduino_GFX *panel = new Arduino_AXS15231B(bus, GFX_NOT_DEFINED, 0, false, 320, 480);
  canvas = new Arduino_Canvas(320, 480, panel, 0, 0, 0);
  if (!canvas->begin(40000000UL)) while (true) delay(1000);
  canvas->fillScreen(0);
  canvas->flush();
  canvasPixels = canvas->getFramebuffer();

  ledcAttach(DESK_TFT_BACKLIGHT, 5000, 8);
  ledcWrite(DESK_TFT_BACKLIGHT, 210);
  touch.begin();
  lv_init();
  lv_tick_set_cb([]() -> uint32_t { return millis(); });
  const size_t displayBytes = DESK_SCREEN_WIDTH * DESK_SCREEN_HEIGHT * sizeof(lv_color_t);
  lv_color_t *displayBuffer = static_cast<lv_color_t *>(heap_caps_malloc(displayBytes, MALLOC_CAP_SPIRAM));
  if (!displayBuffer) while (true) delay(1000);
  lv_display_t *display = lv_display_create(DESK_SCREEN_WIDTH, DESK_SCREEN_HEIGHT);
  lv_display_set_flush_cb(display, displayFlush);
  lv_display_set_buffers(display, displayBuffer, nullptr, displayBytes, LV_DISPLAY_RENDER_MODE_FULL);
  lv_indev_t *input = lv_indev_create();
  lv_indev_set_type(input, LV_INDEV_TYPE_POINTER);
  lv_indev_set_read_cb(input, touchRead);
  createUI();
}

void loop() {
  if (!Serial) hostRecognized = false;
  pollSerial();
  lv_timer_handler();
  if (pendingSwipe) {
    const int direction = pendingSwipe;
    pendingSwipe = 0;
    if (lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) navigatePage(activePage + direction);
  }
  updatePageTransition();
  const uint32_t frameNow = millis();
  if (!fpsWindowStartedAt) fpsWindowStartedAt = frameNow;
  if (frameNow - fpsWindowStartedAt >= DESK_FPS_WINDOW_MS) {
    // Require an actual animation burst. Sparse static-page invalidations are
    // not a frame cadence and must not overwrite the last measured active FPS.
    if (activeRenderIntervalCount >= 3 && activeRenderIntervalTotalMs > 0) {
      measuredFPS = activeRenderIntervalCount * 1000.0f / activeRenderIntervalTotalMs;
    }
    activeRenderIntervalCount = 0;
    activeRenderIntervalTotalMs = 0;
    fpsWindowStartedAt = frameNow;
  }
  static uint32_t lastGameFrame = 0;
  if (millis() - lastGameFrame >= 100) {
    lastGameFrame = millis();
    if (activePage == 0 && lv_obj_has_flag(alertOverlay, LV_OBJ_FLAG_HIDDEN)) updateGame();
    else gameLastTick = millis();
  }
  static uint32_t lastAlertFrame = 0;
  if (millis() - lastAlertFrame >= 100) {
    lastAlertFrame = millis();
    updateAlertAnimation();
  }
  static uint32_t lastFreshness = 0;
  if (millis() - lastFreshness >= 1000) {
    lastFreshness = millis();
    updateFreshness();
  }
  static uint32_t lastTelemetry = 0;
  if (millis() - lastTelemetry >= 5000) {
    lastTelemetry = millis();
    sendDeviceTelemetry();
  }
  delay(8);
}
