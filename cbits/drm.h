#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <errno.h>
#include <math.h>
#include <linux/vt.h>
#include <sys/ioctl.h>


void set_ctm(int, uint32_t, float *);
uint32_t find_crtc(int);
