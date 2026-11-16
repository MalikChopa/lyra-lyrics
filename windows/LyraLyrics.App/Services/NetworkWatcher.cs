using System.Net.NetworkInformation;

namespace LyraLyrics.App.Services;

/// <summary>Disponibilité du réseau (équivalent de NWPathMonitor). L'événement est rappelé sur un fil du système : l'appelant doit rebondir sur l'interface.</summary>
internal sealed class NetworkWatcher : IDisposable
{
    public event Action<bool>? Changed;
    public bool IsOnline { get; private set; }

    public NetworkWatcher()
    {
        IsOnline = NetworkInterface.GetIsNetworkAvailable();
        NetworkChange.NetworkAvailabilityChanged += OnChanged;
    }

    private void OnChanged(object? sender, NetworkAvailabilityEventArgs e)
    {
        IsOnline = e.IsAvailable;
        Changed?.Invoke(e.IsAvailable);
    }

    public void Dispose() => NetworkChange.NetworkAvailabilityChanged -= OnChanged;
}
