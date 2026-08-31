import React, { useCallback, useMemo, useRef, useState } from 'react';
import useNuiEvent from '../../hooks/useNuiEvent';
import { fetchNui } from '../../utils/fetchNui';
import { Locale } from '../../store/locale';
import { getItemUrl } from '../../helpers';
import { imagepath } from '../../store/imagepath';
import WeightBar from '../utils/WeightBar';
import CustomizeHelp from './CustomizeHelp';

interface CustomizeAttachment {
  slot: number;
  name: string;
  label: string;
  count: number;
  image?: string;
  kind: 'component' | 'tint';
}

interface CustomizeSlot {
  id: string;
  label: string;
  oxType: string;
  attached?: { name: string; label: string } | null;
  available: CustomizeAttachment[];
}

interface CustomizeState {
  slot: number;
  name: string;
  label: string;
  serial?: string;
  durability?: number;
  ammo?: number;
  ammoType?: string;
  damage?: number;
  fireRate?: number;
  accuracy?: number;
  range?: number;
  tint?: string | number;
  components: string[];
  slots: CustomizeSlot[];
}

const SLOT_LAYOUT: Record<string, { top: string; left: string; line: string }> = {
  suppressor: { top: '38%', left: '62%', line: 'left' },
  muzzle: { top: '52%', left: '64%', line: 'left' },
  scope: { top: '22%', left: '48%', line: 'down' },
  flashlight: { top: '62%', left: '46%', line: 'up' },
  barrel: { top: '30%', left: '34%', line: 'right' },
  magazine: { top: '58%', left: '34%', line: 'right' },
  grip: { top: '70%', left: '52%', line: 'up' },
  skin: { top: '42%', left: '28%', line: 'right' },
  tint: { top: '54%', left: '26%', line: 'right' },
};

const WeaponCustomize: React.FC = () => {
  const [state, setState] = useState<CustomizeState | null>(null);
  const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
  const [infoVisible, setInfoVisible] = useState(false);
  const dragRef = useRef<{ active: boolean; lastX: number; moved: boolean }>({
    active: false,
    lastX: 0,
    moved: false,
  });

  useNuiEvent<CustomizeState>('openWeaponCustomize', (data) => {
    setState(data);
    setSelectedSlotId((prev) => (prev && data.slots.some((slot) => slot.id === prev) ? prev : null));
  });

  useNuiEvent('closeWeaponCustomize', () => {
    setState(null);
    setSelectedSlotId(null);
    setInfoVisible(false);
  });

  const selectedSlot = useMemo(
    () => state?.slots.find((slot) => slot.id === selectedSlotId) ?? null,
    [state, selectedSlotId]
  );

  const attachedList = useMemo(() => {
    if (!state) return [];
    return state.slots
      .filter((slot) => slot.attached)
      .map((slot) => ({ id: slot.id, slotLabel: slot.label, label: slot.attached!.label }));
  }, [state]);

  const availableList = useMemo(() => {
    if (!state) return [];
    const list: { key: string; slotLabel: string; label: string; count: number }[] = [];
    for (const slot of state.slots) {
      for (const item of slot.available) {
        list.push({
          key: `${slot.id}-${item.slot}-${item.name}`,
          slotLabel: slot.label,
          label: item.label,
          count: item.count,
        });
      }
    }
    return list;
  }, [state]);

  const selectedLayout = selectedSlot
    ? SLOT_LAYOUT[selectedSlot.id] || { top: '50%', left: '50%', line: 'left' }
    : null;

  const close = useCallback(() => {
    fetchNui('weaponCustomizeClose');
  }, []);

  const onStageMouseDown = (e: React.MouseEvent) => {
    if (e.button !== 0 || e.target !== e.currentTarget) return;
    dragRef.current = { active: true, lastX: e.clientX, moved: false };
  };

  const onStageMouseMove = (e: React.MouseEvent) => {
    if (!dragRef.current.active) return;
    const delta = e.clientX - dragRef.current.lastX;
    dragRef.current.lastX = e.clientX;
    if (Math.abs(delta) < 1) return;
    dragRef.current.moved = true;
    fetchNui('weaponCustomizeRotate', { delta: delta * 0.4 });
  };

  const onStageMouseUp = () => {
    dragRef.current.active = false;
  };

  const onStageClick = (e: React.MouseEvent) => {
    if (e.target !== e.currentTarget) return;
    if (dragRef.current.moved) {
      dragRef.current.moved = false;
      return;
    }
    setSelectedSlotId(null);
  };

  if (!state) return null;

  const clampStat = (value?: number) =>
    typeof value === 'number' ? Math.max(0, Math.min(100, Math.floor(value))) : undefined;

  const statBars = [
    { key: 'durability', label: Locale.ui_durability || 'Durability', value: clampStat(state.durability) },
    { key: 'damage', label: Locale.ui_damage || 'Damage', value: clampStat(state.damage) },
    { key: 'fireRate', label: Locale.ui_fire_rate || 'Fire rate', value: clampStat(state.fireRate) },
    { key: 'accuracy', label: Locale.ui_accuracy || 'Accuracy', value: clampStat(state.accuracy) },
    { key: 'range', label: Locale.ui_range || 'Range', value: clampStat(state.range) },
  ].filter((stat) => stat.value !== undefined);

  return (
    <div className="weapon-customize">
      <div className="wc-info">
        <h1>{state.label}</h1>
        <div className="divider" />
        {state.ammoType ? (
          <p className="wc-meta">
            {Locale.ammo_type || 'Ammo type'}: {state.ammoType}
            {state.ammo !== undefined ? ` (${state.ammo})` : ''}
          </p>
        ) : state.ammo !== undefined ? (
          <p className="wc-meta">
            {Locale.ui_ammo || 'Ammo'}: {state.ammo}
          </p>
        ) : null}
        {state.serial ? (
          <p className="wc-meta">
            {Locale.ui_serial || 'Serial number'}: {state.serial}
          </p>
        ) : null}
        {statBars.length > 0 ? (
          <div className="wc-stats">
            {statBars.map((stat) => (
              <div key={stat.key} className="wc-stat">
                <p className="wc-meta">
                  {stat.label}: {stat.value}%
                </p>
                <div className="wc-stat-bar">
                  <WeightBar percent={stat.value!} durability />
                </div>
              </div>
            ))}
          </div>
        ) : null}
        <p className="wc-meta">{Locale.ui_customize_rotate || 'Drag to rotate'}</p>
        <div className="wc-attachments">
          <p className="wc-meta wc-attachments-title">{Locale.ui_customize_equipped || 'Equipped'}</p>
          {attachedList.length > 0 ? (
            <ul className="wc-attachments-list">
              {attachedList.map((entry) => (
                <li key={entry.id}>
                  <span className="wc-attachments-slot">{entry.slotLabel}</span>
                  <span className="wc-attachments-value">{entry.label}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="wc-attachments-empty">{Locale.ui_customize_none || 'None'}</p>
          )}
        </div>
        <div className="wc-attachments">
          <p className="wc-meta wc-attachments-title">{Locale.ui_customize_available || 'Available'}</p>
          {availableList.length > 0 ? (
            <ul className="wc-attachments-list">
              {availableList.map((entry) => (
                <li key={entry.key}>
                  <span className="wc-attachments-slot">{entry.slotLabel}</span>
                  <span className="wc-attachments-value">
                    {entry.label}
                    {entry.count > 1 ? ` ×${entry.count}` : ''}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="wc-attachments-empty">{Locale.ui_customize_no_inventory || 'None in inventory'}</p>
          )}
        </div>
        <button type="button" className="wc-back" onClick={close}>
          {Locale.ui_customize_back || 'Back to inventory'}
        </button>
      </div>

      <div
        className="wc-stage"
        onMouseDown={onStageMouseDown}
        onMouseMove={onStageMouseMove}
        onMouseUp={onStageMouseUp}
        onMouseLeave={onStageMouseUp}
        onClick={onStageClick}
      >
        {state.slots.map((slot) => {
          const layout = SLOT_LAYOUT[slot.id] || { top: '50%', left: '50%', line: 'left' };
          const active = selectedSlotId === slot.id;
          return (
            <button
              key={slot.id}
              type="button"
              className={`wc-slot wc-slot-${layout.line}${active ? ' active' : ''}${slot.attached ? ' filled' : ''}`}
              style={{ top: layout.top, left: layout.left }}
              onClick={(e) => {
                e.stopPropagation();
                setSelectedSlotId(slot.id);
              }}
            >
              <span className="wc-slot-label">{slot.label}</span>
              {slot.attached ? <span className="wc-slot-attached">{slot.attached.label}</span> : null}
            </button>
          );
        })}

        {selectedSlot && selectedLayout ? (
          <div
            className={`wc-actions wc-actions-${selectedLayout.line}`}
            style={{ top: selectedLayout.top, left: selectedLayout.left }}
            onClick={(e) => e.stopPropagation()}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="wc-actions-header">
              <span>{selectedSlot.label}</span>
              <button type="button" className="wc-actions-close" onClick={() => setSelectedSlotId(null)}>
                ×
              </button>
            </div>

            {selectedSlot.attached ? (
              <div className="wc-actions-equipped">
                <div className="wc-actions-equipped-text">
                  <span className="wc-actions-label">{Locale.ui_customize_equipped || 'Equipped'}</span>
                  <span className="wc-actions-value">{selectedSlot.attached.label}</span>
                </div>
                <button
                  type="button"
                  className="wc-remove"
                  onClick={(e) => {
                    e.stopPropagation();
                    fetchNui('weaponCustomizeRemove', {
                      component: selectedSlot.attached?.name,
                    });
                  }}
                >
                  {Locale.ui_customize_remove || 'Remove'}
                </button>
              </div>
            ) : (
              <p className="wc-actions-hint">{Locale.ui_customize_add || 'Select an attachment to add'}</p>
            )}

            <div className="wc-actions-list">
              {selectedSlot.available.length > 0 ? (
                selectedSlot.available.map((item) => (
                  <button
                    key={`${item.slot}-${item.name}`}
                    type="button"
                    className="wc-actions-item"
                    onClick={(e) => {
                      e.stopPropagation();
                      fetchNui('weaponCustomizeApply', { slot: item.slot });
                    }}
                  >
                    <img
                      src={item.image || getItemUrl(item.name) || `${imagepath}/${item.name.toLowerCase()}.png`}
                      alt={item.label}
                      draggable={false}
                      onError={(e) => {
                        (e.target as HTMLImageElement).style.display = 'none';
                      }}
                    />
                    <span>{item.label}</span>
                  </button>
                ))
              ) : (
                <p className="wc-empty">{Locale.ui_customize_empty || 'No compatible attachments'}</p>
              )}
            </div>
          </div>
        ) : null}
      </div>

      <button type="button" className="useful-controls-button wc-help-button" onClick={() => setInfoVisible(true)}>
        <svg xmlns="http://www.w3.org/2000/svg" height="2em" viewBox="0 0 524 524">
          <path d="M256 512A256 256 0 1 0 256 0a256 256 0 1 0 0 512zM216 336h24V272H216c-13.3 0-24-10.7-24-24s10.7-24 24-24h48c13.3 0 24 10.7 24 24v88h8c13.3 0 24 10.7 24 24s-10.7 24-24 24H216c-13.3 0-24-10.7-24-24s10.7-24 24-24zm40-208a32 32 0 1 1 0 64 32 32 0 1 1 0-64z" />
        </svg>
      </button>
      <CustomizeHelp infoVisible={infoVisible} setInfoVisible={setInfoVisible} />
    </div>
  );
};

export default WeaponCustomize;
