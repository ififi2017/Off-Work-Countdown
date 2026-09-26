package com.rainif.doneat.plus

import android.app.Activity
import android.content.Context
import com.rainif.doneat.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class PlusPlan { MONTHLY, YEARLY, LIFETIME }
data class PlusOffer(val plan: PlusPlan, val price: String, val description: String)
data class PlusStoreState(val status: PlusStatus = PlusStatus.LOADING, val offers: List<PlusOffer> = emptyList(),
    val busy: Boolean = false, val hasPurchasedBefore: Boolean = false, val operationFailed: Boolean = false) {
    val authorized: Boolean get() = status == PlusStatus.SUBSCRIBED || status == PlusStatus.LIFETIME
}

/** The sole purchase gate shared by every paid screen. */
class PlusAccess(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val repository = PlayBillingRepository(context.applicationContext, scope)
    val state: StateFlow<PlusStoreState> = repository.state
    private val _authorized = MutableStateFlow(repository.state.value.authorized || PlusDebugOverride.read(context))
    val authorized: StateFlow<Boolean> = _authorized.asStateFlow()
    private val _collectsObservations = MutableStateFlow(_authorized.value || !repository.state.value.hasPurchasedBefore)
    /** Mirrors iOS until D-07 changes: free users collect, lapsed buyers pause. */
    val collectsObservations: StateFlow<Boolean> = _collectsObservations.asStateFlow()

    init {
        scope.launch { repository.state.collect {
            val granted = it.authorized || PlusDebugOverride.read(context)
            _authorized.value = granted
            _collectsObservations.value = granted || !it.hasPurchasedBefore
        } }
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isNotBlank()) scope.launch { repository.refresh() }
    }

    fun refresh() { scope.launch { repository.refresh() } }
    fun restore() { scope.launch { repository.refresh() } }
    fun purchase(activity: Activity, plan: PlusPlan) { scope.launch { repository.purchase(activity, plan) } }
    fun setDebugAuthorized(value: Boolean) {
        if (!PlusDebugOverride.AVAILABLE) return
        PlusDebugOverride.write(context, value)
        _authorized.value = value || state.value.authorized
        _collectsObservations.value = _authorized.value || !state.value.hasPurchasedBefore
    }
}
