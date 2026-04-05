#include "SwiftXMLCoderCShim.h"

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
