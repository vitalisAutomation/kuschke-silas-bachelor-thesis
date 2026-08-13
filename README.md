# bachelor-thesis-silas-kuschke
Implementation of x86 and arm64 build snaps for industrial ctrlX controller from Bosch Rexroth

Hallo Anton,

schaue Dir bitte den main-branch an. Dort liegt der aktuell funktionierende Code. im Ordner sdk-vm-automation liegt die Batch-Datei install_sdk.bat. Öffne diese Datei in einem neuen Ordner, wo nichts Anderes als diese Datei enthalten ist. Führe die Datei via Doppelclick aus. Das ist das Setup-Skript, was eine VM mit SDK bereitstellt. Das Skript lädt automatisch alle notwendigen Softwarepakete auf die virtuelle Maschine. Du kannst auch zwischen unterschiedlichen Versionen von ctrlX OS auswählen und mehrere virtuelle Maschinen erstellen (ähnlich zu ctrlX Works).

Wichtig: Vor der Ausführung des Batch-Skriptes den RB Local Proxy Manager aktivieren. Des Weiteren muss beim ersten Ausführen des Skriptes QEMU in den Projektordner installiert werden, den Du neu erstellt hast.

Was noch nicht fertig ist: 

Aktuell muss man sich manuell mit der virtuellen Maschinen über die VS-Code Extension Remote SSH verbinden. Das möchte ich noch in das Skript integrieren. Das Ziel soll am Ende sein: Skript wird geöffnet --> Offenes VS-Code Fenster auf der virtuellen Maschine, sodass man direkt Snaps entwickeln kann.

Cross-Compiling: Die Bibliotheken, die keine fertigen Wheel-Dateien besitzen müssen über einen Emulator auf der virtuellen Maschine kompiliert werden. Das funktioniert erst teilweise. Das möchte ich noch optimieren.

Was fertig ist und funktioniert (Skripte in diesem Ordner):

Im Ordner ctrlx-app-installation-automation kannst Du im Terminal die install.py ausführen, um einen Snap auf einer Core zu installieren. Das habe ich mehrfach erfolgreich getestet.

Vorgehensweise, um dieses Skript verwenden zu können:
Im VS-Code Terminal: In Ordner ctrlx-app-installation-automation wechseln dann
                            python -m venv .venv
                            .\.venv\Scripts\Activate.ps1
                            python -m pip install --upgrade pip
                            pip install -r requirements.txt
                            python .\install_snap.py

Nun kann man die IP-Adresse der Core eingeben. Des Weiteren muss der absolute Dateipfad des Snaps angegeben werden, der installiert werden soll. Ich habe im Ordner ctrlx-app-installation-automation ein C++ Hello World beigefügt, dass in den Logs der Core ein Hello World ausgibt. Mit diesem Snap kannst Du dieses Skript testen.

Im Ordner ctrlx-licensing-installation kannst Du mehrere Lizenzdateien auf mehrere Cores installieren. Erstelle hierzu im Ordner ctrlx-licensing-installation einen Unterordner namens licenses und lege dort die Lizenz-Dateien ab. Gehe im VS-Code-Terminal mittels cd in den Ordner ctrlx-licensing-installation und führe folgende Befehle aus:
    .\.venv\Scripts\Activate.ps1
    python .\install_license.py

Nun kann zwischen einer oder mehrerer Cores ausgewählt werden. Des Weiteren können die IP-Adressen automatisch in einer Liste gespeichert werden, sodass man sie nicht immer händisch eingeben muss. Das Skript ermittelt aufgrund der Seriennummern die passende Lizenz-Datei und lädt sie auf die korrespondierende Core. Diese Skript habe ich erfolgreich mehrfach getestet (allerdings nur mit einer Core).

Der Ordner ctrlx-flask-app-test enthält ein Test-Skript, um den Operating-Mode einer einzelnen Core via REST-API zu ändern. Es diente nur Testzwecken funktioniert aber. Inbetriebnahme: Gehe im VS-Code Terminal via cd in den Ordner ctrlx-flask-app-test und führe folgende Befehle aus:
    .\.venv\Scripts\Activate.ps1
    python .\app.py

Der Ordner ctrlx-test-app-for-deployment enthält einen Webserver als Snap verpackt, um den Operating Modus der Core auf der Core zu verändern. Des Weiteren fragt er Speicher- und CPU-Auslastung ab. Der Snap funktioniert aktuell noch nicht und war nur zum Testen gedacht.

Der Ordner docs enthält diverse Dokumentationen zu einzelnen Funktionen. Zum Aufrufen gehe in den Ordner /docs/_build/html und führe folgenden Befehl aus:
    start index.html

Zum Thema KI:

Ich habe Copilot als Chat mit den Skills aus Deinem Repo in VS-Code zum Laufen gebracht. Ich muss allerdings noch aus meinen Python-Skripten Skills erzeugen.

Ich werde nach meiner Bachelorarbeit noch How-Tos zu den Skripten und dem Batch-Skript erstellen und sie in Deinem Tool hochladen.
