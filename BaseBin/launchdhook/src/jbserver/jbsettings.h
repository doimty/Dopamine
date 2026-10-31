#include <xpc/xpc.h>

int jbsettings_get(const char *key, xpc_object_t *valueOut);
int jbsettings_set(const char *key, xpc_object_t value);

// 读取 TrollStoreLite 修复开关，启动流程按本次快照处理。
bool trollstore_lite_fix_enabled(void);

// 读取黑名单 App 的 spinlock 隔离开关（默认开启）。
bool spinlock_safe_isolation_enabled(void);
