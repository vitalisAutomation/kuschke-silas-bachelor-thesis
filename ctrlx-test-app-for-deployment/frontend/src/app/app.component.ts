import { Component, OnInit, OnDestroy, HostListener, ElementRef } from '@angular/core';
import { DashboardService } from './dashboard.service';
import { Subscription, interval } from 'rxjs';
import { startWith, switchMap } from 'rxjs/operators';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit, OnDestroy {
  // Originalstruktur des Metrik-Objekts
  metrics: any = {
    state: 'UNKNOWN',
    cpu: 0,
    ram_used_percent: 0,
    storage_used_percent: 0
  };

  // UI-Zustand
  isDropdownOpen: boolean = false;
  loading: boolean = false;
  errorMessage: string | null = null;
  
  private pollingSub!: Subscription;

  constructor(
    private dashboardService: DashboardService,
    private eRef: ElementRef // Benötigt, um Klicks außerhalb des Menüs zu erkennen
  ) {}

  ngOnInit(): void {
    // Polling: Alle 3 Sekunden automatisch die Metriken frisch von Flask holen
    this.pollingSub = interval(3000).pipe(
      startWith(0),
      switchMap(() => this.dashboardService.getMetrics())
    ).subscribe({
      next: (data: any) => {
        this.metrics.state = data.state || 'UNKNOWN';
        this.metrics.cpu = data.cpu !== undefined ? data.cpu : 0;
        this.metrics.ram_used_percent = data.ram_used_percent !== undefined ? data.ram_used_percent : 0;
        this.metrics.storage_used_percent = data.storage_used_percent !== undefined ? data.storage_used_percent : 0;
      },
      error: (err: any) => {
        this.errorMessage = 'Verbindung zum ctrlX Dashboard-Backend verloren.';
        console.error(err);
      }
    });
  }

  // Schließt das Dropdown, wenn man außerhalb des Indikators klickt
  @HostListener('document:click', ['$event'])
  clickout(event: any) {
    if (!this.eRef.nativeElement.contains(event.target)) {
      this.isDropdownOpen = false;
    }
  }

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
        this.metrics.state = res.state;
        this.loading = false;
      },
      error: (err: any) => {
        this.errorMessage = `Umschalten in den Modus '${targetState}' wurde von der CORE abgelehnt.`;
        this.loading = false;
        console.error(err);
      }
    });
  }

  // Original-Formatierungshilfe für die Gauge-Füllung
  formatValue(val: any): string {
    if (val === undefined || val === null || val === 'N/A') return '0';
    const clean = String(val).replace('%', '');
    const num = parseFloat(clean);
    return isNaN(num) ? '0' : num.toFixed(0);
  }

  ngOnDestroy(): void {
    if (this.pollingSub) {
      this.pollingSub.unsubscribe();
    }
  }
}
