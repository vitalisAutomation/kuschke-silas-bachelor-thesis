import { Component, OnInit, OnDestroy, HostListener, ElementRef } from '@angular/core';
import { DashboardService } from './dashboard.service';
import { Subscription } from 'rxjs'; // 'interval' wird nicht mehr benötigt

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit, OnDestroy {
  // Originalstruktur des Metrik-Objekts bleibt absolut identisch
  metrics: any = {
    state: 'UNKNOWN',
    cpu: 0,
    ram_used_percent: 0,
    storage_used_percent: 0
  };

  // UI-Zustand bleibt identisch
  isDropdownOpen: boolean = false;
  loading: boolean = false;
  errorMessage: string | null = null;
  
  // Umbenannt von pollingSub zu wsSubscription, da wir nun auf WebSockets lauschen
  private wsSubscription!: Subscription;

  constructor(
    private dashboardService: DashboardService,
    private eRef: ElementRef // Benötigt, um Klicks außerhalb des Menüs zu erkennen
  ) {}

  ngOnInit(): void {
    // REAKTIVE WEBSOCKET-INTEGRATION:
    // Wir lauschen passiv auf den Echtzeit-Datenstrom von Flask.
    // Das entlastet die ctrlX CORE massiv von unnötigen HTTP-Pollings.
    this.wsSubscription = this.dashboardService.getLiveMetrics().subscribe({
      next: (data: any) => {
        this.metrics.state = data.state || 'UNKNOWN';
        this.metrics.cpu = data.cpu !== undefined ? data.cpu : 0;
        this.metrics.ram_used_percent = data.ram_used_percent !== undefined ? data.ram_used_percent : 0;
        this.metrics.storage_used_percent = data.storage_used_percent !== undefined ? data.storage_used_percent : 0;
        
        // Lösche eine eventuell bestehende Fehlermeldung, sobald wieder Live-Daten reinkommen
        this.errorMessage = null;
      },
      error: (err: any) => {
        this.errorMessage = 'Verbindung zum ctrlX Dashboard-Backend verloren.';
        console.error(err);
      }
    });
  }

  // Schließt das Dropdown, wenn man außerhalb des Indikators klickt (Originalmethode)
  @HostListener('document:click', ['$event'])
  clickout(event: any) {
    if (!this.eRef.nativeElement.contains(event.target)) {
      this.isDropdownOpen = false;
    }
  }

  // Öffnet/Schließt das Dropdown (Originalmethode)
  toggleDropdown(): void {
    if (!this.loading) {
      this.isDropdownOpen = !this.isDropdownOpen;
    }
  }

  // State-Switch Handler für die Dropdown-Elemente
  onStateChange(targetState: string): void {
    if (this.metrics.state === targetState) return;

    this.loading = true;
    this.isDropdownOpen = false;
    this.errorMessage = null;

    this.dashboardService.setSchedulerState(targetState).subscribe({
      next: (res: any) => {
        // HINWEIS: Wir müssen 'this.metrics.state' hier nicht manuell setzen!
        // Sobald die Umschaltung auf der Steuerung erfolgreich war, pusht Flask 
        // augenblicklich das neue Datenpaket über die WebSockets an uns zurück.
        // Das UI aktualisiert sich dadurch vollkommen automatisch und ohne Verzögerung.
        this.loading = false;
      },
      error: (err: any) => {
        this.errorMessage = `Umschalten in den Modus '${targetState}' wurde von der CORE abgelehnt.`;
        this.loading = false;
        console.error(err);
      }
    });
  }

  // Original-Formatierungshilfe für die Gauge-Füllung (Originalmethode)
  formatValue(val: any): string {
    if (val === undefined || val === null || val === 'N/A') return '0';
    const clean = String(val).replace('%', '');
    const num = parseFloat(clean);
    return isNaN(num) ? '0' : num.toFixed(0);
  }

  ngOnDestroy(): void {
    // Sauber deabonnieren beim Verlassen der Komponente, um Speicherlecks zu verhindern
    if (this.wsSubscription) {
      this.wsSubscription.unsubscribe();
    }
  }
}
