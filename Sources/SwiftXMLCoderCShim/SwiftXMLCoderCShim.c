#include "SwiftXMLCoderCShim.h"

void swiftxmlcoder_xml_free_xml_char(xmlChar * _Nullable pointer) {
    if (pointer != NULL) {
        xmlFree(pointer);
    }
}
