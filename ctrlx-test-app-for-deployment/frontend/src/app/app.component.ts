import { Component, OnInit, OnDestroy } from '@angular/core';
import { DashboardService } from './dashboard.service';
import { Subscription, interval } from 'rxjs';
import { startWith, switchMap } from 'rxjs/operators';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit, OnDestroy {
  // System-Metriken
  currentState: string = 'UNKNOWN';
  cpuUsage: number | string = '0';
  ramUsage: number | string = '0';
  storageUsage: number | string = '0';

  // UI-Statusvariablen
  loading: boolean = false;
  errorMessage: string | null = null;
  
  private pollingSub!: Subscription;

  constructor(private dashboardService: DashboardService) {}

  ngOnInit(): void {
    // Polling: Alle 3 Sekunden automatisch die Metriken frisch von Flask holen
    this.pollingSub = interval(3000).pipe(
      startWith(0),
      switchMap(() => this.dashboardService.getMetrics())
    ).subscribe({
      next: (data: any) => {
        this.currentState = data.state || 'UNKNOWN';
        this.cpuUsage = data.cpu !== undefined ? data.cpu : 'N/A';
        this.ramUsage = data.ram_used_percent !== undefined ? data.ram_used_percent : 'N/A';
        this.storageUsage = data.storage_used_percent !== undefined ? data.storage_used_percent : 'N/A';
      },
      error: (err: any) => {
        this.errorMessage = 'Verbindung zum ctrlX Dashboard-Backend verloren.';
        console.error(err);
      }
    });
  }

  // State-Switch Handler für die Buttons
  onStateChange(targetState: string): void {
    this.loading = true;
    this.errorMessage = null;

    this.dashboardService.setSchedulerState(targetState).subscribe({
      next: (res: any) => {
        this.currentState = res.state;
        this.loading = false;
      },
      error: (err: any) => {
        this.errorMessage = `Umschalten in den Modus '${targetState}' wurde von der CORE abgelehnt.`;
        this.loading = false;
        console.error(err);
      }
    });
  }

  ngOnDestroy(): void {
    if (this.pollingSub) {
      this.pollingSub.unsubscribe();
    }
  }
}
