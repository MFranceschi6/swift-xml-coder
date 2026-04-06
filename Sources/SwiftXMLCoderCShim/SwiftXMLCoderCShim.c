#include "SwiftXMLCoderCShim.h"

// Initialise libxml2 at library-load time, in a single-threaded context,
// before any Swift or user code runs. This is the only reliable way to
// avoid a SEGV when multiple threads concurrently access libxml2 APIs for
// the first time: under ThreadSanitizer, TSan's pthread interceptors can
// interfere with libxml2's own internal pthread_once guard, leaving the
// encoding-handler table in a NULL state when xmlGetCharEncodingHandler is
// subsequently called from a concurrent thread.
//
// By forcing full initialisation here (including the UTF-8 handler warm-up),
// we guarantee that the global tables are populated before any thread is
// created, making the subsequent calls in LibXML2.ensureInitialized() no-ops.
__attribute__((constructor))
static void swiftxmlcoder_auto_init_libxml2(void) {
    xmlInitParser();
    // Pre-warm the encoding handler for UTF-8 so that libxml2's lazy table
    // population (xmlGetCharEncodingHandler) never runs on a concurrent thread.
    xmlCharEncodingHandlerPtr handler = xmlFindCharEncodingHandler("UTF-8");
    if (handler != NULL) {
        xmlCharEncCloseFunc(handler);
    }
}

void swiftxmlcoder_xml_free_xml_char(xmlChar * _Nullable pointer) {
    if (pointer != NULL) {
        xmlFree(pointer);
    }
}

void swiftxmlcoder_warm_encoding_handler(const char * _Nonnull encoding) {
    xmlCharEncodingHandlerPtr handler = xmlFindCharEncodingHandler(encoding);
    if (handler != NULL) {
        xmlCharEncCloseFunc(handler);
    }
}
