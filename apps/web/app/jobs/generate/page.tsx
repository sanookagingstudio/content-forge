'use client';

import { useState, useEffect } from 'react';
import { api } from '../../../src/lib/api';

type Platform = 'facebook' | 'instagram' | 'tiktok' | 'youtube';

type GenerateRequest = {
  brandId: string;
  personaId?: string;
  topic: string;
  objective: string;
  platforms: Platform[];
  options?: {
    language?: 'th' | 'en';
    tone?: string;
    length?: 'short' | 'medium' | 'long';
  };
};

type GeneratedContent = {
  caption_th: string;
  platforms: {
    facebook?: { title: string; hook: string; body: string; cta: string; hashtags: string[] };
    instagram?: { title: string; hook: string; body: string; cta: string; hashtags: string[] };
    tiktok?: { title: string; hook: string; body: string; cta: string; hashtags: string[] };
    youtube?: { title: string; hook: string; body: string; cta: string; hashtags: string[] };
  };
  video_script: {
    hook: string;
    storyline: Array<{ scene: string; duration: string; visual: string }>;
    ending_cta: string;
  };
  image_prompt: {
    description_th: string;
    style: string;
    negative_prompt: string;
    notes: string;
  };
};

type Advisory = {
  warnings: string[];
  suggestions: string[];
};

export default function GenerateContentPage() {
  const [brands, setBrands] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState<GenerateRequest>({
    brandId: '',
    topic: '',
    objective: '',
    platforms: ['facebook'],
    options: { language: 'th' },
  });
  const [result, setResult] = useState<{ job: any; advisory: Advisory; outputs: GeneratedContent } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<Platform | 'video' | 'image'>('facebook');

  const loadBrands = async () => {
    const res = await api.listBrands();
    if (res.ok) {
      setBrands(res.data);
      if (res.data.length > 0 && !formData.brandId) {
        setFormData({ ...formData, brandId: res.data[0].id });
      }
    }
  };

  useEffect(() => {
    loadBrands();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setResult(null);

    try {
      const res = await api.generateJob(formData);
      if (res.ok) {
        setResult({
          job: res.data,
          advisory: res.data.advisory || { warnings: [], suggestions: [] },
          outputs: res.data.outputs,
        });
      } else {
        setError(res.error?.message || 'Generation failed');
      }
    } catch (err: any) {
      setError(err.message || 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    alert('Copied to clipboard!');
  };

  return (
    <div style={{ maxWidth: 1200, margin: '0 auto', padding: 24 }}>
      <h1 style={{ marginTop: 0 }}>Generate Content</h1>

      <form onSubmit={handleSubmit} style={{ marginBottom: 32 }}>
        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', marginBottom: 4 }}>
            <strong>Brand:</strong>
          </label>
          <select
            value={formData.brandId}
            onChange={(e) => setFormData({ ...formData, brandId: e.target.value })}
            required
            style={{ width: '100%', padding: 8 }}
          >
            <option value="">Select brand...</option>
            {brands.map((b) => (
              <option key={b.id} value={b.id}>
                {b.name}
              </option>
            ))}
          </select>
        </div>

        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', marginBottom: 4 }}>
            <strong>Topic (หัวข้อ):</strong>
          </label>
          <input
            type="text"
            value={formData.topic}
            onChange={(e) => setFormData({ ...formData, topic: e.target.value })}
            required
            placeholder="e.g., การออกกำลังกายสำหรับผู้สูงอายุ"
            style={{ width: '100%', padding: 8 }}
          />
        </div>

        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', marginBottom: 4 }}>
            <strong>Objective (วัตถุประสงค์):</strong>
          </label>
          <textarea
            value={formData.objective}
            onChange={(e) => setFormData({ ...formData, objective: e.target.value })}
            required
            placeholder="e.g., เพิ่มการรับรู้เกี่ยวกับสุขภาพของผู้สูงอายุ"
            style={{ width: '100%', padding: 8, minHeight: 80 }}
          />
        </div>

        <div style={{ marginBottom: 16 }}>
          <label style={{ display: 'block', marginBottom: 4 }}>
            <strong>Platforms:</strong>
          </label>
          <div style={{ display: 'flex', gap: 16 }}>
            {(['facebook', 'instagram', 'tiktok', 'youtube'] as Platform[]).map((p) => (
              <label key={p} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <input
                  type="checkbox"
                  checked={formData.platforms.includes(p)}
                  onChange={(e) => {
                    if (e.target.checked) {
                      setFormData({ ...formData, platforms: [...formData.platforms, p] });
                    } else {
                      setFormData({ ...formData, platforms: formData.platforms.filter((x) => x !== p) });
                    }
                  }}
                />
                {p.charAt(0).toUpperCase() + p.slice(1)}
              </label>
            ))}
          </div>
        </div>

        <button
          type="submit"
          disabled={loading || !formData.brandId || !formData.topic || !formData.objective}
          style={{ padding: '12px 24px', fontSize: 16, cursor: loading ? 'not-allowed' : 'pointer' }}
        >
          {loading ? 'Generating...' : 'Generate Content'}
        </button>
      </form>

      {error && (
        <div style={{ padding: 16, background: '#fee', border: '1px solid #fcc', marginBottom: 24 }}>
          <strong>Error:</strong> {error}
        </div>
      )}

      {result && (
        <div>
          {/* Jarvis Advisory */}
          {(result.advisory.warnings.length > 0 || result.advisory.suggestions.length > 0) && (
            <div style={{ marginBottom: 24, padding: 16, background: '#fff9e6', border: '1px solid #ffd700' }}>
              <h3 style={{ marginTop: 0 }}>⚠️ Jarvis Advisory</h3>
              {result.advisory.warnings.length > 0 && (
                <div style={{ marginBottom: 12 }}>
                  <strong>Warnings:</strong>
                  <ul>
                    {result.advisory.warnings.map((w, i) => (
                      <li key={i}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}
              {result.advisory.suggestions.length > 0 && (
                <div>
                  <strong>Suggestions:</strong>
                  <ul>
                    {result.advisory.suggestions.map((s, i) => (
                      <li key={i}>{s}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}

          {/* Results Tabs */}
          <div style={{ borderBottom: '1px solid #ddd', marginBottom: 16 }}>
            {formData.platforms.map((p) => (
              <button
                key={p}
                onClick={() => setActiveTab(p)}
                style={{
                  padding: '8px 16px',
                  border: 'none',
                  background: activeTab === p ? '#0070f3' : 'transparent',
                  color: activeTab === p ? 'white' : 'inherit',
                  cursor: 'pointer',
                }}
              >
                {p.charAt(0).toUpperCase() + p.slice(1)}
              </button>
            ))}
            <button
              onClick={() => setActiveTab('video')}
              style={{
                padding: '8px 16px',
                border: 'none',
                background: activeTab === 'video' ? '#0070f3' : 'transparent',
                color: activeTab === 'video' ? 'white' : 'inherit',
                cursor: 'pointer',
              }}
            >
              Video Script
            </button>
            <button
              onClick={() => setActiveTab('image')}
              style={{
                padding: '8px 16px',
                border: 'none',
                background: activeTab === 'image' ? '#0070f3' : 'transparent',
                color: activeTab === 'image' ? 'white' : 'inherit',
                cursor: 'pointer',
              }}
            >
              Image Prompt
            </button>
          </div>

          {/* Platform Content */}
          {activeTab !== 'video' && activeTab !== 'image' && result.outputs.platforms[activeTab] && (
            <div style={{ padding: 16, background: '#f9f9f9', borderRadius: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <h3 style={{ margin: 0 }}>{activeTab.charAt(0).toUpperCase() + activeTab.slice(1)} Content</h3>
                <button onClick={() => copyToClipboard(JSON.stringify(result.outputs.platforms[activeTab], null, 2))}>
                  Copy
                </button>
              </div>
              <div style={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 14 }}>
                <div><strong>Title:</strong> {result.outputs.platforms[activeTab]?.title}</div>
                <div><strong>Hook:</strong> {result.outputs.platforms[activeTab]?.hook}</div>
                <div><strong>Body:</strong> {result.outputs.platforms[activeTab]?.body}</div>
                <div><strong>CTA:</strong> {result.outputs.platforms[activeTab]?.cta}</div>
                <div><strong>Hashtags:</strong> {result.outputs.platforms[activeTab]?.hashtags.join(' ')}</div>
              </div>
            </div>
          )}

          {/* Video Script */}
          {activeTab === 'video' && (
            <div style={{ padding: 16, background: '#f9f9f9', borderRadius: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <h3 style={{ margin: 0 }}>Video Script</h3>
                <button onClick={() => copyToClipboard(JSON.stringify(result.outputs.video_script, null, 2))}>
                  Copy
                </button>
              </div>
              <div style={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 14 }}>
                <div><strong>Hook:</strong> {result.outputs.video_script.hook}</div>
                <div><strong>Storyline:</strong></div>
                {result.outputs.video_script.storyline.map((s, i) => (
                  <div key={i} style={{ marginLeft: 16, marginBottom: 8 }}>
                    <strong>{s.scene}</strong> ({s.duration}): {s.visual}
                  </div>
                ))}
                <div><strong>Ending CTA:</strong> {result.outputs.video_script.ending_cta}</div>
              </div>
            </div>
          )}

          {/* Image Prompt */}
          {activeTab === 'image' && (
            <div style={{ padding: 16, background: '#f9f9f9', borderRadius: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <h3 style={{ margin: 0 }}>Image Prompt</h3>
                <button onClick={() => copyToClipboard(JSON.stringify(result.outputs.image_prompt, null, 2))}>
                  Copy
                </button>
              </div>
              <div style={{ whiteSpace: 'pre-wrap', fontFamily: 'monospace', fontSize: 14 }}>
                <div><strong>Description (TH):</strong> {result.outputs.image_prompt.description_th}</div>
                <div><strong>Style:</strong> {result.outputs.image_prompt.style}</div>
                <div><strong>Negative Prompt:</strong> {result.outputs.image_prompt.negative_prompt}</div>
                <div><strong>Notes:</strong> {result.outputs.image_prompt.notes}</div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

