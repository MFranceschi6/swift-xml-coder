#ifndef SWIFTXMLCODERCSHIM_H
#define SWIFTXMLCODERCSHIM_H

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/encoding.h>

void swiftxmlcoder_xml_free_xml_char(xmlChar * _Nullable pointer);

/// Forces libxml2 to resolve and cache the encoding handler for a given name.
/// Call once during single-threaded initialization to prevent a race in
/// `xmlGetCharEncodingHandler` when multiple threads create writers concurrently.
void swiftxmlcoder_warm_encoding_handler(const char * _Nonnull encoding);

#endif
