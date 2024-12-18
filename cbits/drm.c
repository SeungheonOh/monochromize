#include "drm.h"

#define DRM_CTM_COEFF_ONE (1LL << 32)  // Fixed-point 32.32 format
#define FIXED_POINT_SCALE (1LL << 32)  // 2^32

int64_t f2fp(float value) {
    // Scale the floating-point value by 2^fractional_bits
    double scaled_value = value * (1LL << 32);

    // Round to the nearest integer
    int64_t fixed_value = (int64_t)round(scaled_value);

    // Return the fixed-point value
    return fixed_value;
}


void set_ctm(int drm_fd, uint32_t crtc_id, float *ctm_matrixf) {
  drmModeObjectProperties *props = drmModeObjectGetProperties(drm_fd, crtc_id, DRM_MODE_OBJECT_CRTC);
  if (!props) {
    perror("Failed to get CRTC properties");
    return;
  }

  uint32_t ctm_property_id = 0;
  for (uint32_t i = 0; i < props->count_props; i++) {
    drmModePropertyRes *prop = drmModeGetProperty(drm_fd, props->props[i]);
    if (!prop)
      continue;

    if (strcmp(prop->name, "CTM") == 0) {
      ctm_property_id = prop->prop_id;
      drmModeFreeProperty(prop);
      break;
    }

    drmModeFreeProperty(prop);
  }

  drmModeFreeObjectProperties(props);

  uint64_t ctm_matrix[9];
  for(int i = 0; i < 9; i++) ctm_matrix[i] = f2fp(ctm_matrixf[i]);

  uint32_t ctm_blob_id;
  if (drmModeCreatePropertyBlob(drm_fd, ctm_matrix, sizeof(ctm_matrix), &ctm_blob_id)) {
    perror("Failed to create CTM property blob");
    return;
  }

  if (drmModeObjectSetProperty(drm_fd, crtc_id, DRM_MODE_OBJECT_CRTC, ctm_property_id, ctm_blob_id) < 0) {
    perror("Failed to set CTM property");
  }
  drmModeDestroyPropertyBlob(drm_fd, ctm_blob_id);
}

uint32_t find_crtc(int drm_fd) {
  drmModeRes *resources = drmModeGetResources(drm_fd);
  if (!resources) {
    perror("Failed to get DRM resources");
    return 0;
  }

  uint32_t crtc_id = 0;
  for (int i = 0; i < resources->count_crtcs; i++) {
    crtc_id = resources->crtcs[i];
    break;
  }

  drmModeFreeResources(resources);
  return crtc_id;
}
