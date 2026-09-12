THEOS_PACKAGE_NAME = com.example.aihuishou.batchfind
ARCHS = arm64
TARGET = iphone:clang:latest:15.0

# variant 由 THEOS_PACKAGE_SCHEME 控制: rootless (默认) / roothide / 留空=rootful
# 推荐直接用 scripts/build.sh，会自动准备 control 文件并设置 scheme。
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AihuishouBatchFind
AihuishouBatchFind_FILES = Tweak.xm \
                           AHBatchFindController.m \
                           AHRealScrapeController.m \
                           AHBatchFindProxy.m \
                           AHCaptureEngine.m \
                           AHRecordStore.m \
                           AHExporter.m \
                           AHProgressHUD.m \
                           AHAppProbe.m
AihuishouBatchFind_FRAMEWORKS = UIKit Foundation
AihuishouBatchFind_LDFLAGS = -lsqlite3
AihuishouBatchFind_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: clean
clean::
	rm -rf $(THEOS_BUILD_DIR) packages