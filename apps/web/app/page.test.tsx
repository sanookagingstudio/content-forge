import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import Dashboard from './page';

describe('Dashboard Page', () => {
  it('renders dashboard title and welcome message', () => {
    render(<Dashboard />);
    
    expect(screen.getByText('Dashboard')).toBeInTheDocument();
    expect(screen.getByText(/Welcome to Content Forge V1 Foundation/)).toBeInTheDocument();
  });

  it('renders navigation links', () => {
    render(<Dashboard />);
    
    expect(screen.getByText(/Brands/)).toBeInTheDocument();
    expect(screen.getByText(/Personas/)).toBeInTheDocument();
    expect(screen.getByText(/Planner/)).toBeInTheDocument();
    expect(screen.getByText(/Jobs/)).toBeInTheDocument();
  });
});

