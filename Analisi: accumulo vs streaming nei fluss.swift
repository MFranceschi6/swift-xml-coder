Analisi: accumulo vs streaming nei flussi
ENCODING — encode(_:): 3 stadi di accumulo completo

Swift Value
  ──[accumulo 1]──→  _XMLTreeElementBox (albero mutabile in memoria)
  ──[accumulo 2]──→  XMLTreeDocument (albero immutabile — copia completa)
  ──[accumulo 3]──→  [XMLStreamEvent] (array completo di eventi)
  ──[accumulo 4]──→  [Data] chunks → Data finale
Il punto critico è in XMLEncoder.swift:285-287:


var events: [XMLStreamEvent] = []
try tree.walkEvents { events.append($0) }
return try writer.write(events)
walkEvents potrebbe emettere eventi one-by-one in modo streaming (accetta una closure emit), ma il chiamante li accumula tutti in un array prima di passarli al writer. A sua volta il writer in XMLStreamWriter+Logic.swift:24-36 accumula chunks: [Data] e poi li unisce.

Risultato: l'intero documento esiste 4 volte contemporaneamente in memoria:

_XMLTreeElementBox (mutabile, durante encode)
XMLTreeElement / XMLTreeDocument (immutabile, dopo makeElement())
[XMLStreamEvent] (array eventi)
[Data] chunks → Data finale
Le copie 1 e 3 sono effimere ma si sovrappongono temporalmente a 2. Non c'è mai un punto in cui i dati "fluiscono" senza accumulo intermedio.