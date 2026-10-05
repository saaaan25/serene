#import "FlexDelegateBridge.h"
#import <dlfcn.h>
#import <stdint.h>

typedef void* (*TfLiteFlexCreateDelegateFn)(void);
typedef void (*TfLiteFlexDeleteDelegateFn)(void*);

static TfLiteFlexCreateDelegateFn _createDelegateFn = NULL;
static TfLiteFlexDeleteDelegateFn _deleteDelegateFn = NULL;
static void* _delegate = NULL;

static void LoadSymbols(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    _createDelegateFn = (TfLiteFlexCreateDelegateFn)dlsym(
      RTLD_DEFAULT, "TfLiteFlexCreateDelegate"
    );
    if (_createDelegateFn == NULL) {
      _createDelegateFn = (TfLiteFlexCreateDelegateFn)dlsym(
        RTLD_DEFAULT, "_TfLiteFlexCreateDelegate"
      );
    }
    _deleteDelegateFn = (TfLiteFlexDeleteDelegateFn)dlsym(
      RTLD_DEFAULT, "TfLiteFlexDeleteDelegate"
    );
    if (_deleteDelegateFn == NULL) {
      _deleteDelegateFn = (TfLiteFlexDeleteDelegateFn)dlsym(
        RTLD_DEFAULT, "_TfLiteFlexDeleteDelegate"
      );
    }
  });
}

@implementation FlexDelegateBridge

+ (int64_t)createDelegate {
  LoadSymbols();
  if (_createDelegateFn == NULL) {
    return 0;
  }
  if (_delegate == NULL) {
    _delegate = _createDelegateFn();
  }
  return (int64_t)(intptr_t)_delegate;
}

+ (void)disposeDelegate {
  LoadSymbols();
  if (_delegate != NULL && _deleteDelegateFn != NULL) {
    _deleteDelegateFn(_delegate);
  }
  _delegate = NULL;
}

@end